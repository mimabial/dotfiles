#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/firmware
Refresh and apply firmware updates via fwupdmgr." "$@"

echo -e "\e[32mUpdate Firmware\e[0m"

if ! command -v fwupdmgr >/dev/null 2>&1; then
  hyprshell pm add fwupd
fi

fwupdmgr refresh
sudo fwupdmgr update
