#!/usr/bin/env bash

set -euo pipefail

# Prefer restarting the watcher service (it owns Waybar lifecycle in this setup).
if systemctl --user is-active --quiet hyprland-waybar-watcher.service 2>/dev/null; then
  state=$(systemctl --user show -p ActiveState --value hyprland-waybar-watcher.service 2>/dev/null || true)
  if [[ "${state}" == "deactivating" ]]; then
    systemctl --user kill --signal=SIGKILL hyprland-waybar-watcher.service >/dev/null 2>&1 || true
  fi
  systemctl --user restart --no-block hyprland-waybar-watcher.service >/dev/null 2>&1 || true
  exit 0
fi

# Fallback: restart Waybar directly (avoid SIGUSR2 reload zombies).
if pgrep -x waybar >/dev/null 2>&1; then
  pkill -x waybar 2>/dev/null || true
fi
uwsm-app -- waybar >/dev/null 2>&1 &
