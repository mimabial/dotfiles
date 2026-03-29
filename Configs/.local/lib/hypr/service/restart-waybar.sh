#!/usr/bin/env bash

set -euo pipefail

waybar_watcher_unit="hyprland-waybar-watcher.service"

if [[ "$(systemctl --user show -p LoadState --value "${waybar_watcher_unit}" 2>/dev/null)" != "loaded" ]]; then
  printf 'ERROR: Waybar watcher unit is not loaded: %s\n' "${waybar_watcher_unit}" >&2
  exit 1
fi

if [[ "$(systemctl --user show -p ActiveState --value "${waybar_watcher_unit}")" == "deactivating" ]]; then
  systemctl --user kill --signal=SIGKILL "${waybar_watcher_unit}"
fi

systemctl --user restart "${waybar_watcher_unit}"
