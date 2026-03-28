#!/usr/bin/env bash

# shellcheck source=/dev/null
if ! source "$(command -v hyprshell)"; then
  echo "[hyprshell] code :: Error: hyprshell not found."
  exit 1
fi

selected_wall="${1:-${WALLPAPER_CURRENT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current}/wall.set}"
[ -z "${selected_wall}" ] && echo "No input wallpaper" && exit 1
selected_wall="$(readlink -f "${selected_wall}")"

# Let's kill all old mpvpaper instances
pkill -O -x mpvpaper || true
mpvpaper -p '*' "${selected_wall}" --fork --mpv-options "no-audio loop --geometry=100%:100% --panscan=1.0"
