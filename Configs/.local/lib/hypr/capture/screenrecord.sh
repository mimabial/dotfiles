#!/usr/bin/env bash
# Screen recording with gpu-screen-recorder
# Supports desktop/mic audio, webcam overlay, auto 4K cap, preview thumbnails

set -eo pipefail

source "$(command -v hyprshell)" || exit 1

[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs

OUTPUT_DIR="${HYPR_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings}"
RECORDING_FILE="${TMPDIR:-/tmp}/hypr-screenrecord-filename"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR" 2>/dev/null || {
    dunstify -a "Screen Recorder" -i "media-record" "Directory error" "Cannot create $OUTPUT_DIR" -u critical
    exit 1
  }
fi

USAGE() {
  cat <<'USAGE'

Usage: hyprshell screenrecord [option]

Options:
    --start                  Start screen recording (portal selection)
    --toggle                 Toggle recording on/off
    --status                 Show recording status (JSON for waybar)
    --quit                   Stop the recording
    --with-desktop-audio     Record desktop audio
    --with-microphone-audio  Record microphone audio
    --audio                  Alias for --with-desktop-audio
    --with-webcam            Show webcam overlay during recording
    --webcam-device=DEV      Specify webcam device (default: auto-detect)
    --resolution=WxH         Override resolution (0x0 for native)
    --window                 Record the focused window (no portal)
    --region                 Select region with slurp (no portal)
    --output                 Record entire focused output (no portal)
    --help                   Show this help message

Examples:
    hyprshell screenrecord --toggle --audio
    hyprshell screenrecord --start --with-desktop-audio --with-microphone-audio
    hyprshell screenrecord --start --with-webcam --audio

Environment:
    HYPR_SCREENRECORD_DIR    Custom output directory (default: ~/Videos/Recordings)

USAGE
}

# --- Webcam ---

screenrecord_webcam_device() {
  local device="${WEBCAM_DEVICE}"
  if [[ -n "$device" ]]; then
    printf '%s\n' "$device"
    return 0
  fi

  device=$(v4l2-ctl --list-devices 2>/dev/null | grep -m1 "^[[:space:]]*/dev/video" | tr -d '\t')
  if [[ -z "$device" ]]; then
    dunstify -a "Screen Recorder" -i "camera-web" "No webcam devices found" -u critical -t 3000
    return 1
  fi

  printf '%s\n' "$device"
}

screenrecord_webcam_target_width() {
  local scale
  scale=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .scale')
  awk "BEGIN {printf \"%.0f\", 360 * $scale}"
}

screenrecord_webcam_video_size_arg() {
  local device="$1"
  local preferred_resolutions=("640x360" "1280x720" "1920x1080")
  local video_size_arg=""
  local available_formats
  available_formats=$(v4l2-ctl --list-formats-ext -d "$device" 2>/dev/null)

  for resolution in "${preferred_resolutions[@]}"; do
    if grep -q "$resolution" <<<"$available_formats"; then
      video_size_arg="-video_size $resolution"
      break
    fi
  done

  printf '%s\n' "${video_size_arg}"
}

start_webcam_overlay() {
  cleanup_webcam

  local device=""
  local target_width=""
  local video_size_arg=""
  device="$(screenrecord_webcam_device)" || return 1
  target_width="$(screenrecord_webcam_target_width)"
  video_size_arg="$(screenrecord_webcam_video_size_arg "$device")"

  # shellcheck disable=SC2086
  ffplay -f v4l2 $video_size_arg -framerate 30 "$device" \
    -vf "crop=iw/2:ih,scale=${target_width}:-1" \
    -window_title "WebcamOverlay" \
    -noborder \
    -fflags nobuffer -flags low_delay \
    -probesize 32 -analyzeduration 0 \
    -loglevel quiet &
}

cleanup_webcam() {
  pkill -f "WebcamOverlay" 2>/dev/null || true
}

write_recording_state() {
  printf '%s:::%s\n' "$1" "$2" >"$RECORDING_FILE"
}

read_recording_state() {
  local state=""

  [[ -f "$RECORDING_FILE" ]] || return 1
  state="$(<"$RECORDING_FILE")"
  [[ "$state" == *':::'* ]] || return 1
  RECORDING_PID="${state%%:::*}"
  RECORDING_PATH="${state#*:::}"
  [[ "${RECORDING_PID}" =~ ^[0-9]+$ ]] || return 1
  [[ -n "${RECORDING_PATH}" ]] || return 1
}

# --- Resolution ---

default_resolution() {
  local width height
  read -r width height < <(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | "\(.width) \(.height)"')
  if ((width > 3840 || height > 2160)); then
    echo "3840x2160"
  else
    echo "0x0"
  fi
}

# --- Window selection ---

workspace_windows() {
  hyprctl -j clients | jq -r --argjson ws "$(hyprctl -j activeworkspace | jq '.id')" \
    '.[] | select(.workspace.id == $ws and .mapped and (.hidden | not)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

select_window() {
  local result_file
  result_file=$(mktemp)
  trap 'rm -f "$result_file"' RETURN

  while true; do
    echo "$(workspace_windows)" | slurp 2>/dev/null >"$result_file" &
    local slurp_pid=$!

    # Watch Hyprland socket for workspace changes, kill slurp to restart
    nc -U "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" 2>/dev/null |
      while IFS= read -r event; do
        [[ "$event" == workspace\>\>* ]] && kill "$slurp_pid" 2>/dev/null && break
      done &
    local watch_pid=$!

    wait "$slurp_pid" 2>/dev/null
    local exit_code=$?
    kill "$watch_pid" 2>/dev/null
    wait "$watch_pid" 2>/dev/null

    local geom
    geom=$(<"$result_file")

    if [[ -n "$geom" ]]; then
      echo "$geom"
      return 0
    fi

    # exit code 1 = user cancelled (Escape/right-click)
    [[ $exit_code -eq 1 ]] && return 1
  done
}

# --- Recording ---

ensure_screen_recorder_available() {
  if ! pkg_installed gpu-screen-recorder; then
    dunstify -a "Screen Recorder" -i "media-record" "gpu-screen-recorder not found" "Install it first" -u critical
    exit 1
  fi
}

screenrecord_audio_args() {
  local -n audio_args_ref="$1"
  local audio_devices=""

  audio_args_ref=()
  [[ "$DESKTOP_AUDIO" == true ]] && audio_devices+="default_output"
  if [[ "$MICROPHONE_AUDIO" == true ]]; then
    [[ -n "$audio_devices" ]] && audio_devices+="|"
    audio_devices+="default_input"
  fi
  [[ -n "$audio_devices" ]] && audio_args_ref=(-a "$audio_devices" -ac aac)
}

screenrecord_base_args() {
  local -n rec_args_ref="$1"
  local resolution="${RESOLUTION:-$(default_resolution)}"
  rec_args_ref=(-w portal -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)
}

screenrecord_formatted_region() {
  awk '{split($1,pos,","); print $2"+"pos[1]"+"pos[2]}'
}

screenrecord_maybe_force_display_gpu() {
  [[ "$USE_REGION" == true || "$USE_OUTPUT" == true || "$USE_WINDOW" == true ]] || return 0
  [[ -z "$(gpu-screen-recorder --list-monitors 2>/dev/null)" ]] || return 0

  local output_name card mesa_vendor
  output_name=$(hyprctl -j monitors | jq -r '.[] | select(.focused==true) | .name')
  for card in /dev/dri/card*; do
    [[ -e "$card" ]] || continue
    if gpu-screen-recorder --list-capture-options "$card" 2>/dev/null | grep -q "$output_name"; then
      mesa_vendor="$(find /usr/share/glvnd/egl_vendor.d/ -name '*mesa*' 2>/dev/null | head -1)"
      [[ -f "$mesa_vendor" ]] && export __EGL_VENDOR_LIBRARY_FILENAMES="$mesa_vendor"
      return 0
    fi
  done
}

screenrecord_window_args() {
  local -n rec_args_ref="$1"
  local resolution="$2"
  local win_geom=""
  local win_formatted=""

  win_geom=$(select_window) || {
    dunstify -a "Screen Recorder" -t 3000 -i "media-record" "Window selection cancelled"
    return 1
  }
  win_formatted=$(screenrecord_formatted_region <<<"$win_geom")
  rec_args_ref=(-w region -region "$win_formatted" -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)
}

screenrecord_region_args() {
  local -n rec_args_ref="$1"
  local resolution="$2"
  local region=""
  local region_formatted=""

  region=$(slurp 2>/dev/null) || {
    dunstify -a "Screen Recorder" -t 3000 -i "media-record" "Region selection cancelled"
    return 1
  }
  region_formatted=$(screenrecord_formatted_region <<<"$region")
  rec_args_ref=(-w region -region "$region_formatted" -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)
}

screenrecord_output_args() {
  local -n rec_args_ref="$1"
  local resolution="$2"
  local output=""

  output=$(hyprctl -j monitors | jq -r '.[] | select(.focused==true) | .name')
  [[ -n "$output" ]] || return 0
  rec_args_ref=(-w "$output" -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)
}

screenrecord_capture_args() {
  local -n rec_args_ref="$1"
  local resolution="$2"

  screenrecord_base_args rec_args_ref
  if [[ "$USE_WINDOW" == true ]]; then
    screenrecord_window_args rec_args_ref "$resolution"
  elif [[ "$USE_REGION" == true ]]; then
    screenrecord_region_args rec_args_ref "$resolution"
  elif [[ "$USE_OUTPUT" == true ]]; then
    screenrecord_output_args rec_args_ref "$resolution"
  fi
}

notify_recording_started() {
  if [[ "$USE_WINDOW" == true || "$USE_REGION" == true || "$USE_OUTPUT" == true ]]; then
    dunstify -a "Screen Recorder" -t 3000 -i "media-record" "Recording started" -h "string:x-dunst-stack-tag:screenrec"
  else
    dunstify -a "Screen Recorder" -t 3000 -i "media-record" "Choose what to record" -h "string:x-dunst-stack-tag:screenrec"
  fi
}

start_recording() {
  local filename="$OUTPUT_DIR/screenrecord-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
  local audio_args=()
  local resolution="${RESOLUTION:-$(default_resolution)}"
  local -a rec_args=()

  ensure_screen_recorder_available
  screenrecord_audio_args audio_args
  screenrecord_maybe_force_display_gpu
  screenrecord_capture_args rec_args "$resolution" || return 1

  gpu-screen-recorder "${rec_args[@]}" -o "$filename" "${audio_args[@]}" &
  local pid=$!
  kill -0 "$pid" 2>/dev/null || return 1

  write_recording_state "$pid" "$filename"
  pkill -RTMIN+8 waybar
  notify_recording_started
}

signal_recording_stop() {
  RECORDING_STOP_PID=""
  RECORDING_STOP_PATH=""
  if read_recording_state; then
    RECORDING_STOP_PID="$RECORDING_PID"
    RECORDING_STOP_PATH="$RECORDING_PATH"
    kill -SIGINT "$RECORDING_STOP_PID" 2>/dev/null || true
    return 0
  fi

  pkill -SIGINT -f "^gpu-screen-recorder"
}

wait_for_recording_stop() {
  [[ -n "$1" && "$1" =~ ^[0-9]+$ ]] || return 0

  if command -v waitpid >/dev/null 2>&1; then
    waitpid -e "$1" 2>/dev/null || true
  else
    tail --pid="$1" -f /dev/null 2>/dev/null || true
  fi
}

finalize_recording_stop() {
  local pid="$1"
  local filename="$2"

  if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
    dunstify -a "Screen Recorder" -i "media-record" "Recording error" "Process had to be force-killed. Video may be corrupted." -u critical -t 5000
  elif [[ -n "$filename" && -f "$filename" ]]; then
    trim_first_frame "$filename"
    notify_recording_saved "$filename"
  fi
}

stop_recording() {
  signal_recording_stop

  pkill -RTMIN+8 waybar
  cleanup_webcam

  (
    wait_for_recording_stop "$RECORDING_STOP_PID"
    finalize_recording_stop "$RECORDING_STOP_PID" "$RECORDING_STOP_PATH"
    rm -f "$RECORDING_FILE"
  ) &
}

trim_first_frame() {
  local latest="$1"
  local trimmed="${latest%.mp4}-trimmed.mp4"

  if ffmpeg -y -ss 0.1 -i "$latest" -c copy "$trimmed" -loglevel quiet 2>/dev/null; then
    mv "$trimmed" "$latest"
  else
    rm -f "$trimmed"
  fi
}

notify_recording_saved() {
  local filename="$1"
  local preview="${filename%.mp4}-preview.png"
  local action=""

  ffmpeg -y -i "$filename" -ss 00:00:00.1 -vframes 1 -q:v 2 "$preview" -loglevel quiet 2>/dev/null

  action=$(dunstify -a "Screen Recorder" "Recording saved" "Click to open" -t 10000 -I "${preview:-$filename}" -A "default,open")
  [[ "$action" == "default" ]] && mpv "$filename"
  rm -f "$preview"
}

is_recording_active() {
  if read_recording_state; then
    kill -0 "$RECORDING_PID" >/dev/null 2>&1 && return 0
    rm -f "$RECORDING_FILE"
  fi

  pgrep -f "^gpu-screen-recorder" >/dev/null 2>&1
}

show_status() {
  if is_recording_active; then
    echo '{"text": "󰑋", "class": "recording", "tooltip": "Recording (click to stop)"}'
  else
    [[ -f "$RECORDING_FILE" ]] && rm -f "$RECORDING_FILE"
    echo '{"text": "󰑋", "class": "idle", "tooltip": "Start recording"}'
  fi
}

# --- Argument parsing ---

DESKTOP_AUDIO=false
MICROPHONE_AUDIO=false
WEBCAM=false
WEBCAM_DEVICE=""
RESOLUTION=""
USE_OUTPUT=false
USE_REGION=false
USE_WINDOW=false
ACTION=""

for arg in "$@"; do
  case "$arg" in
    --start) ACTION="start" ;;
    --toggle) ACTION="toggle" ;;
    --quit) ACTION="quit" ;;
    --status) ACTION="status" ;;
    --help) USAGE; exit 0 ;;
    --audio|--with-desktop-audio) DESKTOP_AUDIO=true ;;
    --with-microphone-audio) MICROPHONE_AUDIO=true ;;
    --with-webcam) WEBCAM=true ;;
    --webcam-device=*) WEBCAM_DEVICE="${arg#*=}" ;;
    --resolution=*) RESOLUTION="${arg#*=}" ;;
    --output) USE_OUTPUT=true ;;
    --region) USE_REGION=true ;;
    --window) USE_WINDOW=true ;;
  esac
done

case "${ACTION:-}" in
  start)
    [[ "$WEBCAM" == true ]] && start_webcam_overlay
    start_recording || cleanup_webcam
    ;;
  toggle)
    if pgrep -x slurp >/dev/null 2>&1; then
      pkill -x slurp 2>/dev/null
    elif is_recording_active; then
      stop_recording
    else
      [[ "$WEBCAM" == true ]] && start_webcam_overlay
      start_recording || cleanup_webcam
    fi
    ;;
  quit)
    stop_recording
    ;;
  status)
    show_status
    ;;
  "")
    if is_recording_active; then
      stop_recording
    else
      [[ "$WEBCAM" == true ]] && start_webcam_overlay
      start_recording || cleanup_webcam
    fi
    ;;
esac
