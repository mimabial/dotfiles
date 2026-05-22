#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/monitor.common.bash"

monitor_focused_name
