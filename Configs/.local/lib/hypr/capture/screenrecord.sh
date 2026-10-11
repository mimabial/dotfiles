#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/capture/lib/selection.bash"
hypr_runtime_require system || exit 1

[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs

SLURP_EXIT_CANCELLED=1
OUTPUT_DIR="${HYPR_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings}"
SCREENRECORD_USER_ID="${UID}"
SCREENRECORD_RUNTIME_DIR="${HYPR_RUNTIME_DIR:-}"
if [[ -z "${SCREENRECORD_RUNTIME_DIR}" ]]; then
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    SCREENRECORD_RUNTIME_DIR="${XDG_RUNTIME_DIR}/hypr"
  else
    SCREENRECORD_RUNTIME_DIR="${TMPDIR:-/tmp}/hypr-${SCREENRECORD_USER_ID}"
  fi
fi
SCREENRECORD_SESSION_NAME="${HYPRLAND_INSTANCE_SIGNATURE:-default}"
SCREENRECORD_SESSION_NAME="${SCREENRECORD_SESSION_NAME//[^A-Za-z0-9._-]/_}"
RECORDING_FILE="${SCREENRECORD_RUNTIME_DIR}/screenrecord-${SCREENRECORD_SESSION_NAME}.state"
RECORDING_STATE_SEPARATOR=":::"
SCREENRECORD_LOG_FILE="${SCREENRECORD_RUNTIME_DIR}/screenrecord-${SCREENRECORD_SESSION_NAME}.log"

usage() {
  cat <<'USAGE'

Usage: hyprshell screenrecord [option]

Options:
    --start                  Start screen recording (portal selection)
    --toggle                 Toggle recording on/off
    --status                 Show recording status as bar JSON
    --quit                   Stop the recording
    --with-desktop-audio     Record desktop audio
    --with-microphone-audio  Record microphone audio
    --audio                  Alias for --with-desktop-audio
    --with-webcam            Show webcam overlay during recording
    --webcam-device=DEV      Specify webcam device (default: auto-detect)
    --resolution=WxH         Override resolution (0x0 for native)
    --window                 Record the focused window (no portal)
    --region                 Select region with slurp (no portal)
    --smart                  Smart selection: click a window or drag (no portal)
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

RECORD_MAX_WIDTH=3840
RECORD_MAX_HEIGHT=2160
WEBCAM_OVERLAY_WIDTH=360
RECORDING_SAVED_NOTIFY_MS=10000
RECORDING_START_TRIM_SECONDS=0.1
RECORDING_PREVIEW_FRAME_SECONDS=0.1

source "${HYPR_LIB_DIR}/capture/lib/screenrecord-state.bash"
source "${HYPR_LIB_DIR}/capture/lib/screenrecord-targets.bash"
source "${HYPR_LIB_DIR}/capture/lib/screenrecord-webcam.bash"
source "${HYPR_LIB_DIR}/capture/lib/screenrecord-output.bash"
source "${HYPR_LIB_DIR}/capture/lib/screenrecord-lifecycle.bash"

if [[ ! -d "${SCREENRECORD_RUNTIME_DIR}" ]]; then
  mkdir -p "${SCREENRECORD_RUNTIME_DIR}" 2>/dev/null || {
    screenrecord_notify "Directory error" "Cannot create ${SCREENRECORD_RUNTIME_DIR}" "media-record" "critical" "${NOTIFY_LONG_MS}"
    exit 1
  }
fi

if [[ ! -d "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR" 2>/dev/null || {
    screenrecord_notify "Directory error" "Cannot create $OUTPUT_DIR" "media-record" "critical" "${NOTIFY_LONG_MS}"
    exit 1
  }
fi

DESKTOP_AUDIO=false
MICROPHONE_AUDIO=false
WEBCAM=false
WEBCAM_DEVICE=""
RESOLUTION=""
USE_OUTPUT=false
USE_REGION=false
USE_SMART=false
USE_WINDOW=false
ACTION=""

for arg in "$@"; do
  case "$arg" in
    --start) ACTION="start" ;;
    --toggle) ACTION="toggle" ;;
    --quit) ACTION="quit" ;;
    --status) ACTION="status" ;;
    --help) usage; exit 0 ;;
    --audio|--with-desktop-audio) DESKTOP_AUDIO=true ;;
    --with-microphone-audio) MICROPHONE_AUDIO=true ;;
    --with-webcam) WEBCAM=true ;;
    --webcam-device=*) WEBCAM_DEVICE="${arg#*=}" ;;
    --resolution=*) RESOLUTION="${arg#*=}" ;;
    --output) USE_OUTPUT=true ;;
    --region) USE_REGION=true ;;
    --smart) USE_SMART=true ;;
    --window) USE_WINDOW=true ;;
  esac
done

case "${ACTION:-}" in
  start)
    screenrecord_start_flow
    ;;
  toggle)
    if screenrecord_has_matching_process -x slurp; then
      screenrecord_signal_matching TERM -x slurp
    else
      screenrecord_toggle_flow
    fi
    ;;
  quit)
    stop_recording
    ;;
  status)
    emit_screenrecord_status_json
    ;;
  "")
    screenrecord_toggle_flow
    ;;
esac
