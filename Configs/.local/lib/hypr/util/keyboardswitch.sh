#!/usr/bin/env bash

# shellcheck disable=SC1091
source "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh"

hyprctl switchxkblayout all next

layMain=$(hyprctl -j devices | jq '.keyboards' | jq '.[] | select (.main == true)' | awk -F '"' '{if ($2=="active_keymap") print $4}')
dunstify -a "Keyboard switch" -r 91190 -t 800 -i "${ICONS_DIR}/Pywal16-Icon/keyboard.svg" "${layMain}"
