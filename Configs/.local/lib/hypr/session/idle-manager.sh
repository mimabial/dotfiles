#!/usr/bin/env bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/idle/state.bash"
source "${BASH_SOURCE[0]%/*}/idle/activity.bash"
source "${BASH_SOURCE[0]%/*}/idle/controller.bash"
source "${BASH_SOURCE[0]%/*}/idle/policy.bash"
source "${BASH_SOURCE[0]%/*}/idle/events.bash"

IDLE_DAEMON_WAIT_PID=""
IDLE_WATCHED_DAEMON_PIDS=""
declare -a IDLE_WATCHER_PIDS=()
declare -A idle_manager=([last_mode]="" [last_window_activity]="" [window_state_file]="$(idle_window_state_file)")
IDLE_EVENT_PATH="${idle_manager[window_state_file]}.events.$$"
mkfifo "${IDLE_EVENT_PATH}"
exec {IDLE_EVENT_FD}<>"${IDLE_EVENT_PATH}"

trap 'printf "activity\n" >&"${IDLE_EVENT_FD}"' USR1
trap 'exit 0' INT TERM
trap 'idle_stop_watchers' EXIT

mkdir -p "$(state_dir)"
idle_start_watchers
printf 'activity\n' >&"${IDLE_EVENT_FD}"

while :; do
  IFS= read -r -u "${IDLE_EVENT_FD}" event || continue
  case "${event}" in
    daemon-exit)
      wait "${IDLE_DAEMON_WAIT_PID}" 2>/dev/null || true
      IDLE_DAEMON_WAIT_PID=""
      if [[ "${IDLE_DAEMON_PID}" == "${IDLE_WATCHED_DAEMON_PIDS}" ]]; then
        wait "${IDLE_DAEMON_PID}" 2>/dev/null || true
        IDLE_DAEMON_PID=""
      fi
      ;;
    activity) ;;
    *) exit 1 ;;
  esac
  idle_reconcile_manager idle_manager
  idle_watch_daemon_exit
done
