#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/agent-hub
Focus or launch the Agent Hub TUI, which shows AI coding subscription usage.

The window uses the exact columns and rows that agent-tui reports. The dashboard
does not scroll or stretch, so larger dimensions only add dead space." "$@"

read -r columns rows <<<"$(agent-tui --size 2>/dev/null || true)"
[[ "${columns}" =~ ^[0-9]+$ && "${rows}" =~ ^[0-9]+$ ]] || { columns=72; rows=42; }

exec hyprshell launch/focus.sh org.tui.AgentHub -- \
  hyprshell launch/terminal-present.sh --hypr-cells "${columns}" "${rows}" \
  --app-id org.tui.AgentHub --title "Agent Hub" -- agent-tui
