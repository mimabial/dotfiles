#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require wallpaper_catalog || exit 1

selected_wall="${1:-${WALLPAPER_CURRENT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current}/wall.set}"
[ -z "${selected_wall}" ] && echo "No input wallpaper" && exit 1
selected_wall="$(wallpaper_resolve_path "${selected_wall}")"

mime_type="$(file --mime-type -b "$selected_wall" 2>/dev/null || true)"
if [[ "$mime_type" == video/* ]]; then
  print_log -sec "wallpaper" -stat "converting video" "$selected_wall"
  mkdir -p "${WALLPAPER_VIDEO_DIR}"
  wall_hash="$(${HYPR_HASH_COMMAND:-sha1sum} "$selected_wall")"
  cached_thumb="${WALLPAPER_VIDEO_DIR}/${wall_hash%% *}.png"
  extract_thumbnail "${selected_wall}" "${cached_thumb}"
  selected_wall="${cached_thumb}"
fi

if ! hyprctl hyprpaper reload ",${selected_wall}" >/dev/null 2>&1; then
  if ! hypr_svc_user start hyprpaper; then
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
