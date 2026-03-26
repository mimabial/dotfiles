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

start_webcam_overlay() {
  cleanup_webcam

  local device="${WEBCAM_DEVICE}"
  if [[ -z "$device" ]]; then
    device=$(v4l2-ctl --list-devices 2>/dev/null | grep -m1 "^[[:space:]]*/dev/video" | tr -d '\t')
    if [[ -z "$device" ]]; then
      dunstify -a "Screen Recorder" -i "camera-web" "No webcam devices found" -u critical -t 3000
      return 1
    fi
  fi

  local scale
  scale=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .scale')
  local target_width
  target_width=$(awk "BEGIN {printf \"%.0f\", 360 * $scale}")

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

  # shellcheck disable=SC2086
  ffplay -f v4l2 $video_size_arg -framerate 30 "$device" \
    -vf "crop=iw/2:ih,scale=${target_width}:-1" \
    -window_title "WebcamOverlay" \
    -noborder \
    -fflags nobuffer -flags low_delay \
    -probesize 32 -analyzeduration 0 \
    -loglevel quiet &
  sleep 1
}

cleanup_webcam() {
  pkill -f "WebcamOverlay" 2>/dev/null || true
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

start_recording() {
  if ! pkg_installed gpu-screen-recorder; then
    dunstify -a "Screen Recorder" -i "media-record" "gpu-screen-recorder not found" "Install it first" -u critical
    exit 1
  fi

  local filename="$OUTPUT_DIR/screenrecord-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
  local audio_devices=""
  local audio_args=()

  [[ "$DESKTOP_AUDIO" == true ]] && audio_devices+="default_output"

  if [[ "$MICROPHONE_AUDIO" == true ]]; then
    [[ -n "$audio_devices" ]] && audio_devices+="|"
    audio_devices+="default_input"
  fi

  [[ -n "$audio_devices" ]] && audio_args+=(-a "$audio_devices" -ac aac)

  local resolution="${RESOLUTION:-$(default_resolution)}"
  local -a rec_args=(-w portal -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)

  # On dual-GPU systems, gpu-screen-recorder may pick the wrong card.
  # If auto-detection fails, find the card with connected displays and
  # force Mesa EGL so gpu-screen-recorder uses the display GPU.
  # This must run before region/output modes which bypass the portal.
  if [[ "$USE_REGION" == true || "$USE_OUTPUT" == true || "$USE_WINDOW" == true ]]; then
    if [[ -z "$(gpu-screen-recorder --list-monitors 2>/dev/null)" ]]; then
      local output_name card mesa_vendor
      output_name=$(hyprctl -j monitors | jq -r '.[] | select(.focused==true) | .name')
      for card in /dev/dri/card*; do
        [[ -e "$card" ]] || continue
        if gpu-screen-recorder --list-capture-options "$card" 2>/dev/null | grep -q "$output_name"; then
          mesa_vendor="$(find /usr/share/glvnd/egl_vendor.d/ -name '*mesa*' 2>/dev/null | head -1)"
          [[ -f "$mesa_vendor" ]] && export __EGL_VENDOR_LIBRARY_FILENAMES="$mesa_vendor"
          break
        fi
      done
    fi
  fi

  if [[ "$USE_WINDOW" == true ]]; then
    local win_geom
    win_geom=$(select_window) || { dunstify -a "Screen Recorder" -t 3000 -i "media-record" "Window selection cancelled"; return 1; }
    local win_formatted
    win_formatted=$(awk '{split($1,pos,","); print $2"+"pos[1]"+"pos[2]}' <<<"$win_geom")
    rec_args=(-w region -region "$win_formatted" -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)
  elif [[ "$USE_REGION" == true ]]; then
    local region
    region=$(slurp 2>/dev/null) || { dunstify -a "Screen Recorder" -t 3000 -i "media-record" "Region selection cancelled"; return 1; }
    # slurp returns "X,Y WxH", gpu-screen-recorder wants "WxH+X+Y"
    local region_formatted
    region_formatted=$(awk '{split($1,pos,","); print $2"+"pos[1]"+"pos[2]}' <<<"$region")
    rec_args=(-w region -region "$region_formatted" -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)
  elif [[ "$USE_OUTPUT" == true ]]; then
    local output
    output=$(hyprctl -j monitors | jq -r '.[] | select(.focused==true) | .name')
    if [[ -n "$output" ]]; then
      rec_args=(-w "$output" -k auto -s "$resolution" -f 60 -fm cfr -fallback-cpu-encoding yes)
    fi
  fi

  gpu-screen-recorder "${rec_args[@]}" -o "$filename" "${audio_args[@]}" &
  local pid=$!

  # Wait for recording to start (file appears after portal selection)
  while kill -0 "$pid" 2>/dev/null && [[ ! -f "$filename" ]]; do
    sleep 0.2
  done

  if kill -0 "$pid" 2>/dev/null; then
    echo "$filename" >"$RECORDING_FILE"
    pkill -RTMIN+8 waybar
    dunstify -a "Screen Recorder" -t 3000 -i "media-record" "Recording started" -h "string:x-dunst-stack-tag:screenrec"
  fi
}

stop_recording() {
  pkill -SIGINT -f "^gpu-screen-recorder"

  local count=0
  while pgrep -f "^gpu-screen-recorder" >/dev/null && ((count < 50)); do
    sleep 0.1
    count=$((count + 1))
  done

  pkill -RTMIN+8 waybar
  cleanup_webcam

  if pgrep -f "^gpu-screen-recorder" >/dev/null; then
    pkill -9 -f "^gpu-screen-recorder"
    dunstify -a "Screen Recorder" -i "media-record" "Recording error" "Process had to be force-killed. Video may be corrupted." -u critical -t 5000
  else
    trim_first_frame
    local filename
    filename=$(cat "$RECORDING_FILE" 2>/dev/null)
    local preview="${filename%.mp4}-preview.png"

    ffmpeg -y -i "$filename" -ss 00:00:00.1 -vframes 1 -q:v 2 "$preview" -loglevel quiet 2>/dev/null

    (
      ACTION=$(dunstify -a "Screen Recorder" "Recording saved" "Click to open" -t 10000 -I "${preview:-$filename}" -A "default,open")
      [[ "$ACTION" == "default" ]] && mpv "$filename"
      rm -f "$preview"
    ) &
  fi

  rm -f "$RECORDING_FILE"
}

trim_first_frame() {
  local latest
  latest=$(cat "$RECORDING_FILE" 2>/dev/null)

  if [[ -n "$latest" && -f "$latest" ]]; then
    local trimmed="${latest%.mp4}-trimmed.mp4"
    if ffmpeg -y -ss 0.1 -i "$latest" -c copy "$trimmed" -loglevel quiet 2>/dev/null; then
      mv "$trimmed" "$latest"
    else
      rm -f "$trimmed"
    fi
  fi
}

is_recording_active() {
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
