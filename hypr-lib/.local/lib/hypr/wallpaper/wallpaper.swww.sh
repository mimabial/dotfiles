#!/usr/bin/env bash
# shellcheck disable=SC1091
# Separated wallpaper script for swww backend
# We will handle swww specific configurations here
# add overrides in [wallpaper.swww] in ~/.config/hypr/config.toml

# * Contributor Notes,
# this is a separate implementation of swww wallpaper setter
# If you want to add another backend add it as `wallpaper.<backend>.sh`
# This script only accepts one argument,
#   the path to the wallpaper or a symlink
# This script should handle unsupported files.
#   In this case we used the method `extract_thumbnail`
#   to generate a png from a video file as swww do not support video

selected_wall="${1:-"${WALLPAPER_CURRENT_DIR:-${HYPR_CACHE_HOME:-$HOME/.cache/hypr}/wallpaper/current}/wall.set"}"

# Use flock for robust locking (releases automatically on exit/crash)
SWWW_LOCK="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-swww.lock"
exec 203>"${SWWW_LOCK}"
if ! flock -n 203; then
  echo "Another swww wallpaper operation in progress, skipping..."
  exit 0
fi
trap 'flock -u 203 2>/dev/null' EXIT

scrDir="$(dirname "$(dirname "$(realpath "$0")")")"
# shellcheck disable=SC1091
source "${scrDir}/globalcontrol.sh"

#// set defaults
xtrans="${WALLPAPER_SWWW_TRANSITION_DEFAULT:-fade}"
[[ -z "${xtrans}" ]] && xtrans="fade"

# Handle transition
case "${WALLPAPER_SET_FLAG}" in
  p)
    xtrans="${WALLPAPER_SWWW_TRANSITION_PREV:-$xtrans}"
    ;;
  n)
    xtrans="${WALLPAPER_SWWW_TRANSITION_NEXT:-$xtrans}"
    ;;

esac

[[ -z "${selected_wall}" ]] && echo "No input wallpaper" && exit 1
selected_wall="$(readlink -f "${selected_wall}")"

if ! swww query &>/dev/null; then
  # Close lock file descriptors before starting daemon to prevent inheritance
  swww-daemon --format xrgb 200>&- 201>&- 202>&- 203>&- &
  disown
  swww query && swww restore
fi

is_video=$(file --mime-type -b "${selected_wall}" | grep -c '^video/')
if [[ "${is_video}" -eq 1 ]]; then
  print_log -sec "wallpaper" -stat "converting video" "$selected_wall"
  mkdir -p "${WALLPAPER_VIDEO_DIR}"
  cached_thumb="${WALLPAPER_VIDEO_DIR}/$(${hashMech:-sha1sum} "${selected_wall}" | cut -d' ' -f1).png"
  extract_thumbnail "${selected_wall}" "${cached_thumb}"
  selected_wall="${cached_thumb}"
fi
[[ -z "${wallFramerate}" ]] && wallFramerate=60
[[ -z "${wallTransDuration}" ]] && wallTransDuration=0.6

#// apply wallpaper
# TODO: add support for other backends
print_log -sec "wallpaper" -stat "apply" "$selected_wall"

# Resolve the wallpaper path
resolved_wall="$(readlink -f "$selected_wall")"
if [ -z "${resolved_wall}" ] || [ ! -f "${resolved_wall}" ]; then
  print_log -sec "swww" -err "wallpaper not found: ${selected_wall} -> ${resolved_wall}"
  exit 1
fi

# Get cursor position (fallback to center if unavailable)
cursor_pos="$(hyprctl cursorpos 2>/dev/null | grep -E '^[0-9]' || echo "0,0")"

# Build swww command
swww_cmd=(swww img "${resolved_wall}"
  --transition-bezier .43,1.19,1,.4
  --transition-type "${xtrans}"
  --transition-duration "${wallTransDuration}"
  --transition-fps "${wallFramerate}"
  --invert-y
  --transition-pos "${cursor_pos}")

# Don't run in background during startup to ensure GIF animation loads properly
if [[ "${WALLPAPER_SET_FLAG}" == "start" ]]; then
  "${swww_cmd[@]}"
else
  # Run in background but log any errors
  ( "${swww_cmd[@]}" || print_log -sec "swww" -err "failed to set wallpaper" ) &
fi
