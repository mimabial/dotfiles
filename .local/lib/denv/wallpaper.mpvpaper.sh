#!/usr/bin/env bash

# shellcheck source=$HOME/.local/bin/denv-shell
# shellcheck disable=SC1091
if ! source "$(which denv-shell)"; then
    echo "[wallbash] code :: Error: denv-shell not found."
    echo "[wallbash] code :: Is DENv installed?"
    exit 1
fi

selected_wall="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/denv/wall.set}"
[ -z "${selected_wall}" ] && echo "No input wallpaper" && exit 1
selected_wall="$(readlink -f "${selected_wall}")"

# Let's kill all old mpvpaper instances
pkill -O -x mpvpaper || true
mpvpaper -p '*' "${selected_wall}" --fork --mpv-options "no-audio loop --geometry=100%:100% --panscan=1.0"
