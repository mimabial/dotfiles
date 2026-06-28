#!/usr/bin/env bash
#
# bluetooth.sh — Unblock bluetooth and focus/launch the bluetui TUI.
#
# Usage: bluetooth.sh
#
# Depends on: rfkill, hyprshell launch/{focus,tui}.sh, bluetui
#
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell launch/bluetooth
Unblock bluetooth and focus or launch the bluetui TUI." "$@"

rfkill unblock bluetooth
exec hyprshell launch/focus.sh org.tui.bluetui -- hyprshell launch/tui.sh --app-id org.tui.bluetui -- bluetui
