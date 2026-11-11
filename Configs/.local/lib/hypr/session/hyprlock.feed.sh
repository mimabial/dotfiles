#!/usr/bin/env bash

set -euo pipefail

lock_pid="$1"
[[ "$(<"/proc/${lock_pid}/comm")" == hyprlock ]] || exit 0

MEDIA_CHANGE_FORMAT='{{playerInstance}}{{status}}{{xesam:title}}{{xesam:artist}}{{mpris:length}}{{mpris:artUrl}}'
SLEEP_STATE_CHANGE="type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
SECONDS_PER_MINUTE=60

release_label_pipes_inherited_from_hyprlock() {
  local fd
  for fd in /proc/self/fd/*; do fd=${fd##*/}; ((fd <= 2)) || exec {fd}>&-; done
}

refresh_lock_screen() {
  kill -USR2 "${lock_pid}"
}

refresh_on_media_changes() {
  playerctl -a metadata --format "${MEDIA_CHANGE_FORMAT}" --follow 2>/dev/null |
    while IFS= read -r _; do refresh_lock_screen; done
}

refresh_on_minute_changes() {
  local shown_minute minute now sleep_state_changes
  exec {sleep_state_changes}<> <(exec dbus-monitor --system --profile "${SLEEP_STATE_CHANGE}" 2>/dev/null)
  printf -v shown_minute '%(%H:%M)T' -1
  while printf -v now '%(%s)T' -1; read -r -t "$((SECONDS_PER_MINUTE - now % SECONDS_PER_MINUTE))" -u "${sleep_state_changes}" _ || true; do
    printf -v minute '%(%H:%M)T' -1
    [[ "${minute}" == "${shown_minute}" ]] && continue
    shown_minute="${minute}"
    refresh_lock_screen
  done
}

release_label_pipes_inherited_from_hyprlock
set -m
refresh_on_media_changes &
refresh_on_minute_changes &
waitpid -e "${lock_pid}"
kill %1 %2 2>/dev/null || true
