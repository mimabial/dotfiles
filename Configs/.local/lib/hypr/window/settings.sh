#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell window/settings
Focus or launch the desktop Settings TUI." "$@"

exec "${HYPR_LIB_DIR}/launch/focus.sh" org.tui.Settings -- \
  "${HYPR_LIB_DIR}/launch/tui.sh" --app-id org.tui.Settings --title Settings -- \
  python3 "${HYPR_LIB_DIR}/window/settings/main.py"
