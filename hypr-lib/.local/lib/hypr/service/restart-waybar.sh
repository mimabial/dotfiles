#!/usr/bin/env bash

set -euo pipefail

# Prefer restarting the watcher service (it owns Waybar lifecycle in this setup).
if systemctl --user is-active --quiet hyprland-waybar-watcher.service 2>/dev/null; then
  systemctl --user restart hyprland-waybar-watcher.service
  exit 0
fi

# Fallback: restart Waybar directly (avoid SIGUSR2 reload zombies).
if pgrep -x waybar >/dev/null 2>&1; then
  pkill -x waybar 2>/dev/null || true
fi
uwsm-app -- waybar >/dev/null 2>&1 &
