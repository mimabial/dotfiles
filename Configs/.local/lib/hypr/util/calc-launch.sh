#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell util/calc-launch" "$@"

exec "${HYPR_LIB_DIR}/launch/focus.sh" org.tui.Calc -- bash -ec '
  read -r columns rows < <("${HYPR_LIB_DIR}/util/calc-tui.py" --size)
  exec "${HYPR_LIB_DIR}/launch/terminal-present.sh" \
    --hypr-cells "$columns" "$rows" --app-id org.tui.Calc --title Calculator -- "${HYPR_LIB_DIR}/util/calc-tui.py"
'
