#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/agent-hub
Focus or launch the Agent Hub TUI, which sizes itself to its contents." "$@"

exec hyprshell launch/focus.sh org.tui.AgentHub -- \
  hyprshell launch/terminal-present.sh \
  --app-id org.tui.AgentHub --title "Agent Hub" -- agent-tui
