#!/usr/bin/env bash

wallcache_prepare_queue_directories() {
  mkdir -p "${WALLCACHE_PENDING_DIR}" "${WALLCACHE_RUNNING_DIR}"
}

wallcache_daemon_pid() {
  local pid=""
  if [[ -r "${WALLCACHE_PID_FILE}" ]]; then
    pid="$(<"${WALLCACHE_PID_FILE}")"
  fi
  [[ "${pid}" =~ ^[0-9]+$ ]] || pid=""
  printf '%s' "${pid}"
}

wallcache_daemon_is_running() {
  local pid
  pid="$(wallcache_daemon_pid)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi
  return 1
}

wallcache_start_daemon() {
  wallcache_prepare_queue_directories
  wallcache_daemon_is_running && return 0
  [[ -x "${WALLCACHE_WORKER_SCRIPT}" ]] || return 1

  (nohup bash "$0" --run </dev/null >/dev/null 2>&1 &)
}

wallcache_stop_daemon() {
  local pid
  pid="$(wallcache_daemon_pid)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
  fi
  rm -f "${WALLCACHE_PID_FILE}" 2>/dev/null
}

wallcache_print_status() {
  local pid pending_count running_count
  pending_count=$(find -H "${WALLCACHE_PENDING_DIR}" -maxdepth 1 -type f -name "*.job" 2>/dev/null | wc -l)
  running_count=$(find -H "${WALLCACHE_RUNNING_DIR}" -maxdepth 1 -type f -name "*.job" 2>/dev/null | wc -l)
  pid="$(wallcache_daemon_pid)"
  if wallcache_daemon_is_running; then
    echo "running pid=${pid} pending=${pending_count} running=${running_count}"
  else
    echo "stopped pending=${pending_count} running=${running_count}"
  fi
}

wallcache_wake_daemon() {
  local pid
  pid="$(wallcache_daemon_pid)"
  [[ -n "${pid}" ]] || return 1
  kill -USR1 "${pid}" 2>/dev/null
}

wallcache_wait_for_jobs() {
  local idle_since="$1" remaining_seconds=0 wake_event=""
  remaining_seconds=$((WALLCACHE_IDLE_TIMEOUT - EPOCHSECONDS + idle_since))
  ((remaining_seconds > 0)) || return 1
  IFS= read -r -t "${remaining_seconds}" -u "${wallcache_wake_fd}" wake_event
}

wallcache_run_daemon() {
  local idle_since=0
  local -a cache_args=() running_files=()

  wallcache_prepare_queue_directories
  [[ -x "${WALLCACHE_WORKER_SCRIPT}" ]] || exit 1

  exec {queue_lock_fd}>"${WALLCACHE_LOCK_FILE}"
  flock -n "${queue_lock_fd}" || exit 0

  local wake_pipe="${WALLCACHE_QUEUE_ROOT}/wake.fifo"
  [[ -p "${wake_pipe}" ]] || mkfifo "${wake_pipe}"
  exec {wallcache_wake_fd}<>"${wake_pipe}"
  trap 'printf "\n" >&"${wallcache_wake_fd}"' USR1
  printf '%s\n' "$$" >"${WALLCACHE_PID_FILE}"
  trap 'exit 0' INT TERM
  trap 'wallcache_daemon_cleanup "$?"' EXIT
  wallcache_recover_running_jobs

  idle_since="${EPOCHSECONDS}"
  while :; do
    wallcache_claim_batch cache_args running_files
    if (( ${#running_files[@]} > 0 )); then
      idle_since="${EPOCHSECONDS}"
      wallcache_run_batch cache_args running_files
    else
      wallcache_wait_for_jobs "${idle_since}" || break
    fi
  done
}

wallcache_daemon_cleanup() {
  local exit_code="${1:-$?}"
  trap '' USR1
  exec {wallcache_wake_fd}>&-
  rm -f -- "${WALLCACHE_QUEUE_ROOT}/wake.fifo"
  wallcache_recover_running_jobs
  rm -f "${WALLCACHE_PID_FILE}" 2>/dev/null || true
  flock -u "${queue_lock_fd}" 2>/dev/null || true
  return "${exit_code}"
}
