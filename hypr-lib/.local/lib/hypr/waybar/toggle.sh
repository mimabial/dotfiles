#!/usr/bin/env bash
# Toggle waybar visibility by stopping/starting it
# Tracks state in a file to know whether to show or hide

set -euo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/waybar-hidden"

if [[ -f "$STATE_FILE" ]]; then
  # Waybar is hidden, show it
  rm -f "$STATE_FILE"
  # Start waybar (watcher will handle it if running, otherwise start directly)
  if pgrep -f "waybar.py --watch" >/dev/null 2>&1; then
    # Watcher is running, just need to let it know waybar should start
    # The watcher checks if waybar is running and starts it if not
    :
  else
    waybar &
  fi
else
  # Waybar is visible, hide it
  touch "$STATE_FILE"
  pkill -x waybar 2>/dev/null || true
fi
