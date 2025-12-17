#!/usr/bin/env bash

set -euo pipefail

UNIT="hyprland-keep-awake.service"

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$@"
  fi
}

update_waybar() {
  pkill -RTMIN+21 waybar 2>/dev/null || true
}

if systemctl --user is-active --quiet "${UNIT}" >/dev/null 2>&1; then
  systemctl --user stop "${UNIT}" >/dev/null 2>&1 || true
  notify "Keep awake disabled"
  update_waybar
  exit 0
fi

systemctl --user start "${UNIT}" >/dev/null 2>&1 || true
notify "Keep awake enabled"
update_waybar
