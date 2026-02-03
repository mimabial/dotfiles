#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-}"
if [[ -z "${STATE_DIR}" ]]; then
  STATE_DIR="$HOME/.local/state"
fi
STATE_DIR="${STATE_DIR}/hypr"
KEEP_AWAKE_STATE_FILE="${STATE_DIR}/keep-awake.state"
MANAGER_UNIT="hyprland-idle-manager.service"

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$@"
  fi
}

update_waybar() {
  pkill -RTMIN+21 waybar 2>/dev/null || true
}

systemd_user_ok() {
  systemctl --user is-active default.target >/dev/null 2>&1
}

ensure_manager_running() {
  if systemd_user_ok && systemctl --user list-unit-files "${MANAGER_UNIT}" >/dev/null 2>&1; then
    systemctl --user start --no-block "${MANAGER_UNIT}" >/dev/null 2>&1 || true
  fi
}

keep_awake_enabled() {
  [[ -f "${KEEP_AWAKE_STATE_FILE}" ]]
}

if keep_awake_enabled; then
  rm -f "${KEEP_AWAKE_STATE_FILE}"
  notify "Idle actions enabled"
else
  mkdir -p "${STATE_DIR}"
  printf "%s\n" "1" > "${KEEP_AWAKE_STATE_FILE}"
  notify "Idle actions disabled"
fi

ensure_manager_running
update_waybar
