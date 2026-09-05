#!/usr/bin/env bash
#
# agent-hub.sh — Focus or launch the Agent Hub TUI.
#
# Usage: agent-hub.sh
#
# Depends on: hyprshell launch/{focus,terminal-present}.sh, agent-tui
#
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/agent-hub
Focus or launch the Agent Hub TUI, which shows AI coding subscription usage.

Width is a share of the usable screen; height is the exact number of rows the
cached records need, which agent-tui reports. The dashboard does not scroll and
cannot stretch, so a full-height window just left dead space under the last
section. Cells and percent mix because kitty reads the unit per dimension." "$@"

rows="$(agent-tui --rows 2>/dev/null || true)"
[[ "${rows}" =~ ^[0-9]+$ ]] || rows=42

exec hyprshell launch/focus.sh org.tui.AgentHub -- \
  hyprshell launch/terminal-present.sh --hypr-size 55% "${rows}c" \
  --app-id org.tui.AgentHub --title "Agent Hub" -- agent-tui
