#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell install/xbox-controllers
Install xpadneo for Xbox controller support (reboots when confirmed)." "$@"

hyprshell pm add linux-headers
hyprshell pm aur-add xpadneo-dkms

echo blacklist xpad | sudo tee /etc/modprobe.d/blacklist-xpad.conf >/dev/null
echo hid_xpadneo | sudo tee /etc/modules-load.d/xpadneo.conf >/dev/null

sudo usermod -a -G input "$USER"

gum confirm "Install requires reboot. Ready?" && sudo reboot now
