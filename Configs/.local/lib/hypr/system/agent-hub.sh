#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell system/agent-hub
Focus or launch the Agent Hub TUI." "$@"

exec "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/launch/focus.sh" org.tui.AgentHub -- bash -ec '
  read -r columns rows < <(agent-tui --size)
  exec "$0" \
    --hypr-cells "$columns" "$rows" --app-id org.tui.AgentHub --title "Agent Hub" -- agent-tui
' "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/launch/terminal-present.sh"
