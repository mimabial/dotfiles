#!/usr/bin/env bash

set -euo pipefail

IDLE_UNIT="hyprland-hypridle.service"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/idle.state.sh"
WINDOW_STATE_FILE="$(idle_window_state_file)"
WATCHDOG_INTERVAL="${HYPR_IDLE_MANAGER_WATCHDOG:-60}"
PLAYER_FOLLOW_RETRY="${HYPR_IDLE_MANAGER_PLAYER_RETRY:-2}"
HYPRLAND_FOLLOW_RETRY="${HYPR_IDLE_MANAGER_HYPRLAND_RETRY:-2}"

[[ "${WATCHDOG_INTERVAL}" =~ ^[0-9]+$ ]] || WATCHDOG_INTERVAL=60
[[ "${PLAYER_FOLLOW_RETRY}" =~ ^[0-9]+$ ]] || PLAYER_FOLLOW_RETRY=2
[[ "${HYPRLAND_FOLLOW_RETRY}" =~ ^[0-9]+$ ]] || HYPRLAND_FOLLOW_RETRY=2
(( WATCHDOG_INTERVAL < 1 )) && WATCHDOG_INTERVAL=60
(( PLAYER_FOLLOW_RETRY < 1 )) && PLAYER_FOLLOW_RETRY=2
(( HYPRLAND_FOLLOW_RETRY < 1 )) && HYPRLAND_FOLLOW_RETRY=2

WAKE_SLEEP_PID=""
declare -a WATCHER_PIDS=()

systemd_user_ok() {
  systemctl --user is-active default.target >/dev/null 2>&1
}

audio_playing() {
  command -v playerctl >/dev/null 2>&1 || return 1
  local statuses
  statuses=$'\n'"$(playerctl -a status 2>/dev/null)"$'\n'
  [[ "${statuses}" == *$'\nPlaying\n'* ]]
}

hypridle_active() {
  if systemd_user_ok && systemctl --user is-active --quiet "${IDLE_UNIT}" >/dev/null 2>&1; then
    return 0
  fi
  hypr_user_pgrep -x hypridle >/dev/null 2>&1
}

start_hypridle() {
  if systemd_user_ok && systemctl --user list-unit-files "${IDLE_UNIT}" >/dev/null 2>&1; then
    systemctl --user start "${IDLE_UNIT}" >/dev/null 2>&1 || true
    return 0
  fi

  if hypr_user_pgrep -x hypridle >/dev/null 2>&1; then
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
  hypr_user_pkill -x hypridle >/dev/null 2>&1 || true
}

last_mode=""
last_window_activity=""

publish_window_activity() {
  local activity="${1} ${2}"
  [[ "${activity}" == "${last_window_activity}" ]] && return
  printf '%s\n' "${activity}" >"${WINDOW_STATE_FILE}.tmp"
  mv -f "${WINDOW_STATE_FILE}.tmp" "${WINDOW_STATE_FILE}"
  last_window_activity="${activity}"
}

apply_mode_transition() {
  case "$1" in
    inhibit) stop_hypridle ;;
    idle) start_hypridle ;;
  esac
}

enforce_mode_state() {
  case "$1" in
    inhibit)
      if hypridle_active; then stop_hypridle; fi
      ;;
    idle)
      if ! hypridle_active; then start_hypridle; fi
      ;;
  esac
}

reconcile_mode() {
  local manual_on=0 audio_on=0 window_on=0 fullscreen_active=0 game_active=0 desired_mode=idle
  if idle_manual_enabled; then
    manual_on=1
  fi
  if idle_audio_enabled && audio_playing; then
    audio_on=1
  fi
  if idle_fullscreen_enabled; then
    read -r fullscreen_active game_active < <(idle_window_activity) || true
    ((fullscreen_active || game_active)) && window_on=1
  fi
  publish_window_activity "${fullscreen_active}" "${game_active}"

  if [[ "${manual_on}" -eq 1 || "${audio_on}" -eq 1 || "${window_on}" -eq 1 ]]; then
    desired_mode="inhibit"
  fi

  if [[ "${desired_mode}" != "${last_mode}" ]]; then
    apply_mode_transition "${desired_mode}"
    last_mode="${desired_mode}"
  else
    enforce_mode_state "${desired_mode}"
  fi
}

watch_state_files() {
  command -v inotifywait >/dev/null 2>&1 || return 0
  local state_dir_path=""
  local state_rc_path=""
  state_dir_path="$(state_dir)"
  state_rc_path="$(state_rc_file)"
  mkdir -p "${state_dir_path}"
  (
    set +e
    while :; do
      inotifywait -m -q \
        -e close_write -e create -e delete -e moved_to -e moved_from -e attrib \
        --format '%f' "${state_dir_path}" 2>/dev/null | while IFS= read -r changed_file; do
        case "${changed_file}" in
          "$(basename "${state_rc_path}")")
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

watch_hyprland_events() {
  command -v nc >/dev/null 2>&1 || return 0
  (
    set +e
    while :; do
      socket_path="${XDG_RUNTIME_DIR:-/run/user/${UID}}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
      if [[ ! -S "${socket_path}" ]]; then
        refresh_hypr_instance_signature
        sleep "${HYPRLAND_FOLLOW_RETRY}"
        continue
      fi
      nc -U "${socket_path}" 2>/dev/null | while IFS= read -r event; do
        case "${event}" in
          fullscreen\>\>* | openwindow\>\>* | closewindow\>\>* | movewindow\>\>* | movewindowv2\>\>* | workspace\>\>* | workspacev2\>\>* | focusedmon\>\>* | focusedmonv2\>\>* | changefloatingmode\>\>* | monitoradded\>\>* | monitoraddedv2\>\>* | monitorremoved\>\>* | monitorremovedv2\>\>*)
            kill -USR1 "$$" 2>/dev/null || true
            ;;
        esac
      done
      sleep "${HYPRLAND_FOLLOW_RETRY}"
    done
  ) &
  WATCHER_PIDS+=("$!")
}

cleanup() {
  local exit_code="${1:-$?}"
  if [[ -n "${WAKE_SLEEP_PID}" ]]; then
    kill "${WAKE_SLEEP_PID}" 2>/dev/null || true
  fi
  if ((${#WATCHER_PIDS[@]} > 0)); then
    kill "${WATCHER_PIDS[@]}" 2>/dev/null || true
    wait "${WATCHER_PIDS[@]}" 2>/dev/null || true
  fi
  return "${exit_code}"
}

trap '[[ -n "${WAKE_SLEEP_PID}" ]] && kill "${WAKE_SLEEP_PID}" 2>/dev/null || true' USR1
trap 'exit 0' INT TERM
trap 'cleanup "$?"' EXIT

mkdir -p "$(state_dir)"
watch_state_files
watch_player_events
watch_hyprland_events

reconcile_mode
while :; do
  sleep "${WATCHDOG_INTERVAL}" &
  WAKE_SLEEP_PID="$!"
  wait "${WAKE_SLEEP_PID}" 2>/dev/null || true
  WAKE_SLEEP_PID=""
  reconcile_mode
done
