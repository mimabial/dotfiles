#!/usr/bin/env bash
# Cycle the global tiled layout. Delegates to util/window-layout.sh, which owns the
# layout list and persists the choice in window-layout.lua. This used to set a
# per-workspace rule, but those are runtime-only and any config reload discards them.

set -euo pipefail

HYPR_LIB="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell window/layout-toggle
Cycle the global tiled layout: dwindle -> master -> scrolling -> monocle." "$@"

"${HYPR_LIB}/util/window-layout.sh" --toggle

NEW_LAYOUT="$(hyprctl getoption general:layout -j | jq -r '.str')"

# The waybar module is interval:once, so it only refreshes on its signal.
pkill -RTMIN+22 waybar 2>/dev/null || true
dunstify -a "Hyprland" -t 3000 -i "preferences-system" \
  -h "string:x-dunst-stack-tag:layout" "Layout: ${NEW_LAYOUT}"
