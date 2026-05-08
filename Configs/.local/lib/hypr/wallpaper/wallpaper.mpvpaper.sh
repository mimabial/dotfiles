#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require wallpaper_catalog || exit 1

selected_wall="${1:-${WALLPAPER_CURRENT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current}/wall.set}"
[ -z "${selected_wall}" ] && echo "No input wallpaper" && exit 1
selected_wall="$(wallpaper_resolve_path "${selected_wall}")"

# Let's kill all old mpvpaper instances
pkill -O -x mpvpaper || true
mpvpaper -p '*' "${selected_wall}" --fork --mpv-options "no-audio loop --geometry=100%:100% --panscan=1.0"
