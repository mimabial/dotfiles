#!/usr/bin/env bash

set -euo pipefail

echo -e "\e[32mUpdate Firmware\e[0m"

if ! command -v fwupdmgr >/dev/null 2>&1; then
  sudo pacman -S --noconfirm --needed fwupd
fi

fwupdmgr refresh
sudo fwupdmgr update
