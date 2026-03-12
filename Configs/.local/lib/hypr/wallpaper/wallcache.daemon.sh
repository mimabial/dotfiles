#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# wallcache.daemon.sh
# Queue-based wallpaper thumbnail cache worker with hash deduplication.
#
# Goals:
#   - Deduplicate queued jobs by wallpaper content hash
#   - Batch queued jobs into one swwwallcache invocation
#   - Keep one daemon process per user session
#   - Wake on enqueue notification (event-driven idle wait)
#
# Usage:
#   wallcache.daemon.sh --enqueue -w /path/to/wall.jpg [-w ...]
#   wallcache.daemon.sh --enqueue -t "Theme Name"
#   wallcache.daemon.sh --start
#   wallcache.daemon.sh --stop
#   wallcache.daemon.sh --status
#

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
CACHE_SCRIPT="${LIB_DIR}/hypr/wallpaper/swwwallcache.sh"

QUEUE_ROOT="${XDG_RUNTIME_DIR:-/tmp}/hypr/wallcache"
QUEUE_PENDING_DIR="${QUEUE_ROOT}/pending"
QUEUE_RUNNING_DIR="${QUEUE_ROOT}/running"
QUEUE_PID_FILE="${QUEUE_ROOT}/daemon.pid"
QUEUE_LOCK_FILE="${QUEUE_ROOT}/daemon.lock"

WALLCACHE_BATCH_MAX="${WALLCACHE_BATCH_MAX:-128}"
WALLCACHE_IDLE_TIMEOUT="${WALLCACHE_IDLE_TIMEOUT:-120}"

[[ "${WALLCACHE_BATCH_MAX}" =~ ^[0-9]+$ ]] || WALLCACHE_BATCH_MAX=128
[[ "${WALLCACHE_IDLE_TIMEOUT}" =~ ^[0-9]+$ ]] || WALLCACHE_IDLE_TIMEOUT=120
(( WALLCACHE_BATCH_MAX < 1 )) && WALLCACHE_BATCH_MAX=1
(( WALLCACHE_IDLE_TIMEOUT < 1 )) && WALLCACHE_IDLE_TIMEOUT=120

DAEMON_SLEEP_PID=""
DAEMON_WOKE=0

ensure_queue_dirs() {
  mkdir -p "${QUEUE_PENDING_DIR}" "${QUEUE_RUNNING_DIR}"
}

read_pid_file() {
  local pid=""
  if [[ -r "${QUEUE_PID_FILE}" ]]; then
    pid="$(<"${QUEUE_PID_FILE}")"
  fi
  [[ "${pid}" =~ ^[0-9]+$ ]] || pid=""
  printf '%s' "${pid}"
}

daemon_running() {
  local pid
  pid="$(read_pid_file)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi
  [[ -f "${QUEUE_PID_FILE}" ]] && rm -f "${QUEUE_PID_FILE}"
  return 1
}

thumb_is_ready() {
  local hash="${1}"
  [[ -n "${hash}" ]] || return 1
  [[ -e "${WALLPAPER_THUMB_DIR}/${hash}.thmb" ]] \
    && [[ -e "${WALLPAPER_THUMB_DIR}/${hash}.sqre" ]] \
    && [[ -e "${WALLPAPER_THUMB_DIR}/${hash}.blur" ]] \
    && [[ -e "${WALLPAPER_THUMB_DIR}/${hash}.quad" ]]
}

queue_wallpaper() {
  local wall="${1}"
  local resolved hash job_name job_pending job_running tmp_job

  [[ -n "${wall}" ]] || return 1
  resolved="$(
    readlink -f -- "${wall}" 2>/dev/null \
      || realpath -- "${wall}" 2>/dev/null \
      || printf '%s' "${wall}"
  )"
  [[ -f "${resolved}" ]] || return 1

  hash="$(set_hash "${resolved}" 2>/dev/null)" || return 1
  [[ -n "${hash}" ]] || return 1
  thumb_is_ready "${hash}" && return 0

  job_name="${hash}.job"
  job_pending="${QUEUE_PENDING_DIR}/${job_name}"
  job_running="${QUEUE_RUNNING_DIR}/${job_name}"

  # Hash-level dedup: skip if pending or currently processing.
  [[ -e "${job_pending}" ]] && return 0
  [[ -e "${job_running}" ]] && return 0

  tmp_job="${QUEUE_PENDING_DIR}/.${job_name}.$$"
  printf '%s\n' "${resolved}" >"${tmp_job}" || {
    rm -f "${tmp_job}" 2>/dev/null
    return 1
  }
  if ! mv -n "${tmp_job}" "${job_pending}" 2>/dev/null; then
    rm -f "${tmp_job}" 2>/dev/null
  fi
}

queue_theme() {
  local theme="${1}"
  local theme_dir=""
  local wall

  [[ -n "${theme}" ]] || return 1
  if [[ -d "${theme}" ]]; then
    theme_dir="${theme}"
  elif [[ -d "$(dirname "${HYPR_THEME_DIR}")/${theme}" ]]; then
    theme_dir="$(dirname "${HYPR_THEME_DIR}")/${theme}"
  else
    return 1
  fi

  if ! get_hashmap "${theme_dir}" --no-notify --skipstrays; then
    return 0
  fi

  for wall in "${wallList[@]}"; do
    queue_wallpaper "${wall}"
  done
}

start_daemon() {
  ensure_queue_dirs
  daemon_running && return 0
  [[ -x "${CACHE_SCRIPT}" ]] || return 1

  (nohup bash "$0" --run </dev/null >/dev/null 2>&1 &)

  local _i
  for _i in {1..20}; do
    daemon_running && return 0
    sleep 0.05
  done
  return 1
}

stop_daemon() {
  local pid
  pid="$(read_pid_file)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
  fi
  rm -f "${QUEUE_PID_FILE}" 2>/dev/null
}

status_daemon() {
  local pid pending_count running_count
  pending_count=$(find -H "${QUEUE_PENDING_DIR}" -maxdepth 1 -type f -name "*.job" 2>/dev/null | wc -l)
  running_count=$(find -H "${QUEUE_RUNNING_DIR}" -maxdepth 1 -type f -name "*.job" 2>/dev/null | wc -l)
  pid="$(read_pid_file)"
  if daemon_running; then
    echo "running pid=${pid} pending=${pending_count} running=${running_count}"
  else
    echo "stopped pending=${pending_count} running=${running_count}"
  fi
}

notify_daemon() {
  local pid
  pid="$(read_pid_file)"
  [[ -n "${pid}" ]] || return 1
  kill -USR1 "${pid}" 2>/dev/null
}

run_daemon() {
  ensure_queue_dirs
  [[ -x "${CACHE_SCRIPT}" ]] || exit 1

  exec 206>"${QUEUE_LOCK_FILE}"
  flock -n 206 || exit 0

  printf '%s\n' "$$" >"${QUEUE_PID_FILE}"
  trap 'DAEMON_WOKE=1; [[ -n "${DAEMON_SLEEP_PID}" ]] && kill "${DAEMON_SLEEP_PID}" 2>/dev/null || true' USR1
  trap 'exit 0' INT TERM
  trap '[[ -n "${DAEMON_SLEEP_PID}" ]] && kill "${DAEMON_SLEEP_PID}" 2>/dev/null || true; rm -f "${QUEUE_PID_FILE}"; flock -u 206 2>/dev/null' EXIT

  local idle_since now remaining
  idle_since="$(date +%s)"

  while :; do
    local -a cache_args=()
    local -a running_files=()
    local job_file job_name running_file wall_path wall_hash
    local picked=0

    while IFS= read -r -d '' job_file; do
      (( picked >= WALLCACHE_BATCH_MAX )) && break

      job_name="$(basename "${job_file}")"
      running_file="${QUEUE_RUNNING_DIR}/${job_name}"

      mv -f "${job_file}" "${running_file}" 2>/dev/null || continue

      wall_path="$(head -n1 "${running_file}" 2>/dev/null)"
      wall_hash="${job_name%.job}"
      if [[ -z "${wall_path}" ]] || [[ ! -f "${wall_path}" ]] || [[ -z "${wall_hash}" ]]; then
        rm -f "${running_file}"
        continue
      fi
      if thumb_is_ready "${wall_hash}"; then
        rm -f "${running_file}"
        continue
      fi

      cache_args+=(-w "${wall_path}")
      running_files+=("${running_file}")
      picked=$((picked + 1))
    done < <(find -H "${QUEUE_PENDING_DIR}" -maxdepth 1 -type f -name "*.job" -print0 2>/dev/null | sort -z)

    if (( ${#cache_args[@]} > 0 )); then
      idle_since="$(date +%s)"
      "${CACHE_SCRIPT}" "${cache_args[@]}" &>/dev/null || true
      rm -f -- "${running_files[@]}" 2>/dev/null || true
      continue
    fi

    now="$(date +%s)"
    if (( now - idle_since >= WALLCACHE_IDLE_TIMEOUT )); then
      break
    fi

    remaining=$((WALLCACHE_IDLE_TIMEOUT - (now - idle_since)))
    DAEMON_WOKE=0
    sleep "${remaining}" &
    DAEMON_SLEEP_PID="$!"
    if (( DAEMON_WOKE == 1 )); then
      kill "${DAEMON_SLEEP_PID}" 2>/dev/null || true
    fi
    wait "${DAEMON_SLEEP_PID}" 2>/dev/null || true
    DAEMON_SLEEP_PID=""

    (( DAEMON_WOKE == 1 )) && continue
  done
}

show_help() {
  cat <<EOF
Usage: $(basename "$0") [mode] [options]

Modes:
  --enqueue               Enqueue jobs (default)
  --start                 Start daemon if not running
  --run                   Run daemon loop (internal)
  --stop                  Stop daemon
  --status                Print daemon status

Options for --enqueue:
  -w <wallpaper>          Queue wallpaper path (repeatable)
  -t <theme>              Queue all wallpapers from theme dir

Environment:
  WALLCACHE_BATCH_MAX     Max jobs per daemon batch (default: 128)
  WALLCACHE_IDLE_TIMEOUT  Daemon idle exit timeout seconds (default: 120)
EOF
}

mode="enqueue"
declare -a enqueue_walls=()
declare -a enqueue_themes=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enqueue) mode="enqueue"; shift ;;
    --start) mode="start"; shift ;;
    --run) mode="run"; shift ;;
    --stop) mode="stop"; shift ;;
    --status) mode="status"; shift ;;
    -w)
      [[ -n "${2:-}" ]] || { echo "Missing value for -w" >&2; exit 1; }
      enqueue_walls+=("${2}")
      shift 2
      ;;
    -t)
      [[ -n "${2:-}" ]] || { echo "Missing value for -t" >&2; exit 1; }
      enqueue_themes+=("${2}")
      shift 2
      ;;
    -h | --help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

case "${mode}" in
  run)
    run_daemon
    ;;
  start)
    start_daemon
    ;;
  stop)
    stop_daemon
    ;;
  status)
    ensure_queue_dirs
    status_daemon
    ;;
  enqueue)
    ensure_queue_dirs
    if start_daemon >/dev/null 2>&1; then
      for theme in "${enqueue_themes[@]}"; do
        queue_theme "${theme}" || true
      done
      for wall in "${enqueue_walls[@]}"; do
        queue_wallpaper "${wall}" || true
      done
      if (( ${#enqueue_themes[@]} > 0 || ${#enqueue_walls[@]} > 0 )); then
        notify_daemon >/dev/null 2>&1 || true
      fi
    else
      # Fallback: daemon unavailable, call cache script directly (best effort).
      if [[ -x "${CACHE_SCRIPT}" ]]; then
        declare -a fallback_args=()
        wall=""
        for theme in "${enqueue_themes[@]}"; do
          theme_dir="${theme}"
          if [[ ! -d "${theme_dir}" ]] && [[ -d "$(dirname "${HYPR_THEME_DIR}")/${theme}" ]]; then
            theme_dir="$(dirname "${HYPR_THEME_DIR}")/${theme}"
          fi
          if [[ -d "${theme_dir}" ]] && get_hashmap "${theme_dir}" --no-notify --skipstrays; then
            for wall in "${wallList[@]}"; do
              fallback_args+=(-w "${wall}")
            done
          fi
        done
        for wall in "${enqueue_walls[@]}"; do
          fallback_args+=(-w "${wall}")
        done
        ((${#fallback_args[@]} > 0)) && "${CACHE_SCRIPT}" "${fallback_args[@]}" &>/dev/null &
      fi
    fi
    ;;
esac
