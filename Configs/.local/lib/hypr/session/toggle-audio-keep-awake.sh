#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-}"
if [[ -z "${STATE_DIR}" ]]; then
  STATE_DIR="$HOME/.local/state"
fi
STATE_DIR="${STATE_DIR}/hypr"
AUDIO_STATE_FILE="${STATE_DIR}/keep-awake-audio.state"
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

audio_enabled() {
  if [[ -f "${AUDIO_STATE_FILE}" ]]; then
    local value=""
    value=$(<"${AUDIO_STATE_FILE}")
    [[ "${value}" != "0" ]]
    return
  fi
  return 0
}

mkdir -p "${STATE_DIR}"
if audio_enabled; then
  printf "%s\n" "0" > "${AUDIO_STATE_FILE}"
  notify "Audio keep awake disabled"
else
  printf "%s\n" "1" > "${AUDIO_STATE_FILE}"
  notify "Audio keep awake enabled"
fi

ensure_manager_running
update_waybar
