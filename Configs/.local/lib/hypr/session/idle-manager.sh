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
WATCHDOG_INTERVAL="${HYPR_IDLE_MANAGER_WATCHDOG:-60}"
PLAYER_FOLLOW_RETRY="${HYPR_IDLE_MANAGER_PLAYER_RETRY:-2}"

[[ "${WATCHDOG_INTERVAL}" =~ ^[0-9]+$ ]] || WATCHDOG_INTERVAL=60
[[ "${PLAYER_FOLLOW_RETRY}" =~ ^[0-9]+$ ]] || PLAYER_FOLLOW_RETRY=2
(( WATCHDOG_INTERVAL < 1 )) && WATCHDOG_INTERVAL=60
(( PLAYER_FOLLOW_RETRY < 1 )) && PLAYER_FOLLOW_RETRY=2

WAKE_SLEEP_PID=""
WAKE_SIGNALLED=0
declare -a WATCHER_PIDS=()

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

reconcile_mode() {
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
}

watch_state_files() {
  command -v inotifywait >/dev/null 2>&1 || return 0
  mkdir -p "${STATE_DIR}"
  (
    set +e
    while :; do
      inotifywait -m -q \
        -e close_write -e create -e delete -e moved_to -e moved_from -e attrib \
        --format '%f' "${STATE_DIR}" 2>/dev/null | while IFS= read -r changed_file; do
        case "${changed_file}" in
          "$(basename "${KEEP_AWAKE_STATE_FILE}")" | "$(basename "${AUDIO_STATE_FILE}")")
            kill -USR1 "$$" 2>/dev/null || true
            ;;
        esac
      done || true
      sleep 1
    done
  ) &
  WATCHER_PIDS+=("$!")
}

watch_player_events() {
  command -v playerctl >/dev/null 2>&1 || return 0
  (
    set +e
    while :; do
      playerctl -a --follow status 2>/dev/null | while IFS= read -r _; do
        kill -USR1 "$$" 2>/dev/null || true
      done || true
      sleep "${PLAYER_FOLLOW_RETRY}"
    done
  ) &
  WATCHER_PIDS+=("$!")
}

cleanup() {
  if [[ -n "${WAKE_SLEEP_PID}" ]]; then
    kill "${WAKE_SLEEP_PID}" 2>/dev/null || true
  fi
  if ((${#WATCHER_PIDS[@]} > 0)); then
    kill "${WATCHER_PIDS[@]}" 2>/dev/null || true
    wait "${WATCHER_PIDS[@]}" 2>/dev/null || true
  fi
}

trap 'WAKE_SIGNALLED=1; [[ -n "${WAKE_SLEEP_PID}" ]] && kill "${WAKE_SLEEP_PID}" 2>/dev/null || true' USR1
trap 'exit 0' INT TERM
trap cleanup EXIT

mkdir -p "${STATE_DIR}"
watch_state_files
watch_player_events

reconcile_mode
while :; do
  WAKE_SIGNALLED=0
  sleep "${WATCHDOG_INTERVAL}" &
  WAKE_SLEEP_PID="$!"
  if (( WAKE_SIGNALLED == 1 )); then
    kill "${WAKE_SLEEP_PID}" 2>/dev/null || true
  fi
  wait "${WAKE_SLEEP_PID}" 2>/dev/null || true
  WAKE_SLEEP_PID=""
  reconcile_mode
done
