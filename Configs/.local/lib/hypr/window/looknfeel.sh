#!/usr/bin/env bash
#
# looknfeel.sh — Focus or launch the Look & Feel TUI.
#
# Usage: looknfeel.sh
#
# Depends on: hyprshell launch/{focus,tui}.sh, python3
#
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell window/looknfeel
Focus or launch the Look & Feel TUI, which edits the visual Hyprland keys and
persists them per theme." "$@"

exec hyprshell launch/focus.sh org.tui.Looknfeel -- \
  hyprshell launch/tui.sh --app-id org.tui.Looknfeel --title "Look & Feel" -- \
  python3 "${HYPR_LIB_DIR}/window/lib/looknfeel_tui.py"
