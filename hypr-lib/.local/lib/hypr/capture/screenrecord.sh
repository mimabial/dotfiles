#!/usr/bin/env bash
# Screen recording with wf-recorder

set -eo pipefail

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

# Source user-dirs.dirs for XDG directories
[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs

# Check if wf-recorder is installed
if ! command -v wf-recorder &>/dev/null; then
  notify-send -a "Screen Recorder" "wf-recorder not found" "Install it with: sudo pacman -S wf-recorder" -u critical
  exit 1
fi

RECORDER="wf-recorder"
RECORDING_FILE="${XDG_RUNTIME_DIR:-/tmp}/screenrecord.pid"
OUTPUT_DIR="${OMARCHY_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings}"

# Validate and create output directory
if [[ ! -d "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR" 2>/dev/null || {
    notify-send -a "Screen Recorder" "Directory error" "Cannot create $OUTPUT_DIR" -u critical
    exit 1
  }
fi

USAGE() {
  cat <<USAGE

Usage: hyprshell screenrecord [option]

Using wf-recorder to record the screen.

Options:
    --start         Start screen recording (region selection)
    --toggle        Toggle recording on/off
    --status        Show recording status (JSON for waybar)
    --quit          Stop the recording
    --audio         Record with audio
    --output        Record entire focused output (no selection)
    --help          Show this help message

Examples:
    hyprshell screenrecord --start
    hyprshell screenrecord --start --audio
    hyprshell screenrecord --start --output --audio
    hyprshell screenrecord --toggle --audio

Environment:
    OMARCHY_SCREENRECORD_DIR    Custom output directory (default: ~/Videos/Recordings)

USAGE
}

handle_recording() {
  local use_audio=false
  local use_output=false

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --audio) use_audio=true ;;
      --output) use_output=true ;;
    esac
    shift
  done

  local filename="$OUTPUT_DIR/screenrecord-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
  local parameters=()

  [[ "$use_audio" == true ]] && parameters+=("--audio")

  if [[ "$use_output" == true ]]; then
    local output="$(hyprctl -j monitors | jq -r '.[] | select(.focused==true) | .name')"
    [[ -n "$output" ]] && parameters+=(--output "$output")
  else
    local GEOM="$(slurp -w 0 -b '#00000000' -c '#FFFFFF' -s '#00000055' 2>/dev/null | awk '{
      split($1, pos, ","); x = pos[1]; y = pos[2];
      split($2, size, "x"); width = size[1]; height = size[2];
      if (width >= 16 && height >= 16) print x","y" "width"x"height;
    }')"

    if [[ -z "$GEOM" ]]; then
      notify-send -a "Screen Recorder" "Cancelled" "No region selected"
      return 1
    fi

    parameters+=("--geometry" "$GEOM")
  fi

  wf-recorder "${parameters[@]}" -f "${filename}" &>/dev/null &
  echo $! > "$RECORDING_FILE"
  pkill -RTMIN+8 waybar  # Update indicator
  notify-send -a "Screen Recorder" "Recording started" "Using wf-recorder"
}

stop_recording() {
  if [[ -f "$RECORDING_FILE" ]]; then
    local PID=$(cat "$RECORDING_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      kill -SIGINT "$PID"
      rm "$RECORDING_FILE"
      pkill -RTMIN+8 waybar  # Update indicator
      notify-send -a "Screen Recorder" "Recording saved" "Check $OUTPUT_DIR"
    else
      rm "$RECORDING_FILE"
    fi
  fi
}

is_recording_active() {
  # Check if recording or selection in progress
  if [[ -f "$RECORDING_FILE" ]] && kill -0 $(cat "$RECORDING_FILE") 2>/dev/null; then
    return 0
  elif pgrep -x slurp >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

show_status() {
  if is_recording_active; then
    echo '{"text": "󰑋", "class": "recording", "tooltip": "Recording (click to stop)"}'
  else
    [[ -f "$RECORDING_FILE" ]] && rm "$RECORDING_FILE"
    echo '{"text": "󰑋", "class": "idle", "tooltip": "Start recording"}'
  fi
}

# Main command processing
case "${1:-}" in
  --start)
    shift
    handle_recording "$@"
    ;;
  --toggle)
    shift
    # Smart toggle: cancel slurp if selecting, otherwise toggle recording
    if pgrep -x slurp >/dev/null 2>&1; then
      pkill -x slurp 2>/dev/null
    elif [[ -f "$RECORDING_FILE" ]] && kill -0 $(cat "$RECORDING_FILE") 2>/dev/null; then
      stop_recording
    else
      handle_recording "$@"
    fi
    ;;
  --quit)
    stop_recording
    ;;
  --status)
    show_status
    ;;
  --help|"")
    USAGE
    ;;
  *)
    echo "Unknown option: $1"
    USAGE
    exit 1
    ;;
esac
