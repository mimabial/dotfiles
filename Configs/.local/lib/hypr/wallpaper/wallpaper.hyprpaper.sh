#!/usr/bin/env bash
# A wallpaper backend adapter for hyprpaper
# * Notes
# For future backends, this can be used as a base, just
# change the hyprctl commands for the desired backend's commands

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require wallpaper_catalog || exit 1

selected_wall="${1:-${WALLPAPER_CURRENT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current}/wall.set}"
[ -z "${selected_wall}" ] && echo "No input wallpaper" && exit 1
selected_wall="$(wallpaper_resolve_path "${selected_wall}")"

#? hyprlock do not support videos, so we need to convert them to images
is_video=$(file --mime-type -b "${selected_wall}" | grep -c '^video/')
if [ "${is_video}" -eq 1 ]; then
  print_log -sec "wallpaper" -stat "converting video" "$selected_wall"
  mkdir -p "${WALLPAPER_VIDEO_DIR}"
  cached_thumb="${WALLPAPER_VIDEO_DIR}/$(${HYPR_HASH_COMMAND:-sha1sum} "${selected_wall}" | cut -d' ' -f1).png"
  extract_thumbnail "${selected_wall}" "${cached_thumb}"
  selected_wall="${cached_thumb}"
fi

# ? Setting wallpaper using hyprctl IPC!
# https://wiki.hypr.land/Hypr-Ecosystem/hyprpaper/#the-reload-keyword
if ! hyprctl hyprpaper reload ",${selected_wall}" >/dev/null 2>&1; then
  if ! systemctl --user start hyprpaper.service >/dev/null 2>&1; then
    command -v hyprpaper >/dev/null 2>&1 || {
      print_log -sec "hyprpaper" -err "hyprpaper backend is unavailable"
      exit 1
    }
    setsid hyprpaper >/dev/null 2>&1 &
    disown
  fi

  hyprctl hyprpaper reload ",${selected_wall}" >/dev/null 2>&1 || {
    print_log -sec "hyprpaper" -err "failed to apply wallpaper"
    exit 1
  }
fi
