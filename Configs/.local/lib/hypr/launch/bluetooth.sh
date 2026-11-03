#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell launch/bluetooth
Unblock bluetooth and focus or launch the bluetui TUI." "$@"

rfkill unblock bluetooth
exec "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/launch/focus.sh" org.tui.Bluetui -- \
  "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/launch/tui.sh" --app-id org.tui.Bluetui --title Bluetui -- bluetui
