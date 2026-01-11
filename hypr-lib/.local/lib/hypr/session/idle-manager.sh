#!/usr/bin/env bash

set -euo pipefail

IDLE_UNIT="hyprland-hypridle.service"
STATE_DIR="${XDG_STATE_HOME:-}"
if [[ -z "${STATE_DIR}" ]]; then
  STATE_DIR="$HOME/.local/state"
fi
STATE_DIR="${STATE_DIR}/hypr"
KEEP_AWAKE_STATE_FILE="${STATE_DIR}/keep-awake.state"
AUDIO_STATE_FILE="${STATE_DIR}/keep-awake-audio.state"
POLL_INTERVAL="${HYPR_IDLE_MANAGER_POLL:-2}"

systemd_user_ok() {
  systemctl --user is-active default.target >/dev/null 2>&1
}

manual_active() {
  [[ -f "${KEEP_AWAKE_STATE_FILE}" ]]
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

audio_playing() {
  command -v playerctl >/dev/null 2>&1 || return 1
  playerctl -a status 2>/dev/null | grep -q '^Playing$'
}

hypridle_active() {
  if systemd_user_ok && systemctl --user is-active --quiet "${IDLE_UNIT}" >/dev/null 2>&1; then
    return 0
  fi
  pgrep -x hypridle >/dev/null 2>&1
}

start_hypridle() {
  if systemd_user_ok && systemctl --user list-unit-files "${IDLE_UNIT}" >/dev/null 2>&1; then
    systemctl --user start "${IDLE_UNIT}" >/dev/null 2>&1 || true
    return 0
  fi

  if pgrep -x hypridle >/dev/null 2>&1; then
    return 0
  fi

  if command -v hypridle >/dev/null 2>&1; then
    if command -v uwsm-app >/dev/null 2>&1; then
      uwsm-app -- hypridle >/dev/null 2>&1 &
    else
      hypridle >/dev/null 2>&1 &
    fi
  fi
}

stop_hypridle() {
  if systemd_user_ok && systemctl --user is-active --quiet "${IDLE_UNIT}" >/dev/null 2>&1; then
    systemctl --user stop "${IDLE_UNIT}" >/dev/null 2>&1 || true
    return 0
  fi
  pkill -x hypridle >/dev/null 2>&1 || true
}

last_mode=""

while true; do
  manual_on=0
  audio_on=0
  if manual_active; then
    manual_on=1
  fi
  if audio_enabled && audio_playing; then
    audio_on=1
  fi

  if [[ "${manual_on}" -eq 1 || "${audio_on}" -eq 1 ]]; then
    desired_mode="inhibit"
  else
    desired_mode="idle"
  fi

  if [[ "${desired_mode}" != "${last_mode}" ]]; then
    if [[ "${desired_mode}" == "inhibit" ]]; then
      stop_hypridle
    else
      start_hypridle
    fi
    last_mode="${desired_mode}"
  else
    if [[ "${desired_mode}" == "inhibit" ]]; then
      if hypridle_active; then
        stop_hypridle
      fi
    else
      if ! hypridle_active; then
        start_hypridle
      fi
    fi
  fi

  sleep "${POLL_INTERVAL}"
done
