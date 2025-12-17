#!/usr/bin/env bash

set -euo pipefail

IDLE_UNIT="hyprland-hypridle.service"

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$@"
  fi
}

systemd_user_ok() {
  systemctl --user is-active default.target >/dev/null 2>&1
}

if systemd_user_ok; then
  if systemctl --user is-active --quiet "${IDLE_UNIT}" >/dev/null 2>&1; then
    systemctl --user stop "${IDLE_UNIT}" >/dev/null 2>&1 || true
    notify "Stop locking computer when idle"
    exit 0
  fi

  if systemctl --user list-unit-files "${IDLE_UNIT}" >/dev/null 2>&1; then
    systemctl --user start "${IDLE_UNIT}" >/dev/null 2>&1 || true
    notify "Now locking computer when idle"
    exit 0
  fi
fi

# Fallback: toggle the process directly if systemd user bus/unit isn't available.
if pgrep -x hypridle >/dev/null 2>&1; then
  pkill -x hypridle >/dev/null 2>&1 || true
  notify "Stop locking computer when idle"
else
  if command -v uwsm-app >/dev/null 2>&1; then
    uwsm-app -- hypridle >/dev/null 2>&1 &
  else
    hypridle >/dev/null 2>&1 &
  fi
  notify "Now locking computer when idle"
fi
