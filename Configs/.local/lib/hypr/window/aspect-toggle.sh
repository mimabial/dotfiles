#!/usr/bin/env bash
# Toggle single-window square aspect ratio

set -euo pipefail

CORE_COMMON="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh"
# shellcheck source=/dev/null
source "${CORE_COMMON}" || exit 1

CURRENT_VALUE="$(hyprctl getoption "layout:single_window_aspect_ratio" -j 2>/dev/null | jq -c '.vec2 // [0, 0]')"

if [[ "${CURRENT_VALUE}" == "[1,1]" ]]; then
  hypr_lua_apply 'hl.config({layout = {single_window_aspect_ratio = {0, 0}}})'
  dunstify -a "Hyprland" -t 3000 -i "preferences-system" -h "string:x-dunst-stack-tag:aspect" "Square aspect ratio disabled"
else
  hypr_lua_apply 'hl.config({layout = {single_window_aspect_ratio = {1, 1}}})'
  dunstify -a "Hyprland" -t 3000 -i "preferences-system" -h "string:x-dunst-stack-tag:aspect" "Square aspect ratio enabled"
fi
