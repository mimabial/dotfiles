#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/timezone
Pick a timezone via fzf and set it with timedatectl." "$@"

timezone=$(timedatectl list-timezones | fzf --prompt="Set timezone > " --height=20 --reverse) || exit 1
sudo timedatectl set-timezone "$timezone"
echo "Timezone is now set to $timezone"
hyprshell waybar.py --restart-direct
