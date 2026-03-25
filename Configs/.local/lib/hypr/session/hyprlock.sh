#!/bin/bash

# shellcheck source=$HOME/.local/bin/hyprshell
# shellcheck disable=SC1091
if ! source "$(command -v hyprshell)"; then
  echo "Error: hyprshell not found."
  exit 1
fi

if [[ -z "${XDG_CONFIG_HOME:-}" ]]; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi
if [[ -z "${XDG_CACHE_HOME:-}" ]]; then
  export XDG_CACHE_HOME="$HOME/.cache"
fi
if [[ -z "${XDG_DATA_HOME:-}" ]]; then
  export XDG_DATA_HOME="$HOME/.local/share"
fi

HYPR_CACHE_HOME="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME}/hypr}"
HYPR_LIB_DIR=${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}
WALLPAPER_CACHE_DIR="${WALLPAPER_CACHE_DIR:-${HYPR_CACHE_HOME}/wallpaper}"
WALLPAPER_CURRENT_DIR="${WALLPAPER_CURRENT_DIR:-${WALLPAPER_CACHE_DIR}/current}"
WALLPAPER_VIDEO_DIR="${WALLPAPER_VIDEO_DIR:-${WALLPAPER_CURRENT_DIR}/thumbnails}"
WALLPAPER="${WALLPAPER_CURRENT_DIR}/wall.set"
HYPRLOCK_SCOPE_NAME="${XDG_SESSION_DESKTOP:-unknown}-lockscreen.scope"
HYPRLOCK_USER_DIR="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME}/hypr}/hyprlock"
HYPRLOCK_SHARED_DIR="${HYPR_DATA_HOME:-${XDG_DATA_HOME}/hypr}/hyprlock"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"

USAGE() {
  cat <<EOF
    Usage: $(basename "${0}") --[arg]

    arguments:
      --background -b    - Converts and ensures background to be a png
      --title            - Returns MPRIS song title
      --artist           - Returns MPRIS artist name
      --source           - Returns MPRIS player icon
      --status           - Returns MPRIS play/pause status icon
      --length           - Returns MPRIS song length (MM:SS)
      --profile          - Generates the profile picture
      --art              - Prints the path to the mpris art
      --select      -S   - Selects the hyprlock layout
      --help       -h    - Displays this help message
EOF
}

# Apply ImageMagick limits to avoid OOM during large conversions.
MAGICK_LIMITS=()
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/session/hyprlock.assets.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/session/hyprlock.media.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/session/hyprlock.layout.bash"
resolve_magick_limits
if [ -z "${*}" ]; then
  if [[ ! -f "${WALLPAPER_CURRENT_DIR}/wall.set.png" ]] || ! file -b "${WALLPAPER_CURRENT_DIR}/wall.set.png" 2>/dev/null | grep -q '^PNG'; then
    fn_background || true
  fi

  # Ensure MPRIS fallback wallpaper exists before launching hyprlock
  THUMB="${HYPR_CACHE_HOME}/landing/mpris"
  set_mpris_blurred_empty "${THUMB}.blurred.png"
  # Auto-update profile if .face.icon changed
  fn_profile
  check_and_sanitize_process

  # Lock Bitwarden if running
  if pgrep -x "bitwarden" >/dev/null; then
    bitwarden-desktop --lock &
  fi

  app2unit.sh -u "${HYPRLOCK_SCOPE_NAME}" -t scope -- hyprlock
  exit 0
fi

# Update MPRIS thumbnail in background for all MPRIS-related calls
case "$1" in
  --source)
    # Only update art if last update was >2 seconds ago
    LOCK_FILE="${TMPDIR:-/tmp}/hyprlock-art.lock"
    if [ ! -f "$LOCK_FILE" ] || [ $(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0))) -gt 2 ]; then
      touch "$LOCK_FILE"
      (fn_update_art) &
    fi
    ;;
esac

# Define long options
LONGOPTS="select,background,profile,title,artist,source,status,length,update-art,art,help,test:,test-preview:"

# Parse options
PARSED=$(getopt --options Shb --longoptions $LONGOPTS --name "$0" -- "$@")
if [ $? -ne 0 ]; then
  exit 2
fi

# Apply parsed options
eval set -- "$PARSED"

while true; do
  case "$1" in
    --test)
      layout_test "${2}"
      exit 0
      ;;
    --test-preview)
      rofi_test_preview "${2}"
      exit 0
      ;;
    select | -S | --select)
      fn_select
      exit 0
      ;;
    background | --background | -b)
      fn_background
      exit 0
      ;;
    profile | --profile)
      fn_profile
      exit 0
      ;;
    --title)
      fn_title
      exit 0
      ;;
    --artist)
      fn_artist
      exit 0
      ;;
    --source)
      fn_source
      exit 0
      ;;
    --status)
      fn_status
      exit 0
      ;;
    --length)
      fn_length
      exit 0
      ;;
    --update-art)
      fn_update_art
      exit 0
      ;;
    art | --art)
      fn_art
      exit 0
      ;;
    help | --help | -h)
      USAGE
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
  shift
done
