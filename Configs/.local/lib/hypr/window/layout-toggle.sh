#!/usr/bin/env bash
# Per-workspace layout rules disappear on reload, so persist the global layout.

set -euo pipefail

HYPR_LIB="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell window/layout-toggle
Cycle the global tiled layout: dwindle -> master -> scrolling -> monocle." "$@"

"${HYPR_LIB}/util/window-layout.sh" --toggle

NEW_LAYOUT="$(hyprctl getoption general:layout -j | jq -r '.str')"

dunstify -a "Hyprland" -t 3000 -i "preferences-system" \
  -h "string:x-dunst-stack-tag:layout" "Layout: ${NEW_LAYOUT}"
