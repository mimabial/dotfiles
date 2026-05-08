#!/usr/bin/env bash

set -euo pipefail

timezone=$(timedatectl list-timezones | fzf --prompt="Set timezone > " --height=20 --reverse) || exit 1
sudo timedatectl set-timezone "$timezone"
echo "Timezone is now set to $timezone"
hyprshell waybar.py --restart-direct
