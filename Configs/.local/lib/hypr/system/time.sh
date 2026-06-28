#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/time
Restart systemd-timesyncd to resync the system clock." "$@"

echo "Updating time..."
sudo systemctl restart systemd-timesyncd
