#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

hypr_help_guard "Usage: hyprshell system/monitor-focused
Print the name of the currently focused monitor." "$@"

monitor_focused_name
