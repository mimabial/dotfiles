#!/usr/bin/env bash

set -euo pipefail


# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state wallpaper_catalog || exit 1
hypr_runtime_load_desktop_environment || exit 1

WALLCACHE_WORKER_SCRIPT="${HYPR_LIB_DIR}/wallpaper/wallpaper.cache.sh"

WALLCACHE_QUEUE_ROOT="${XDG_RUNTIME_DIR:-/tmp}/hypr/wallcache"
WALLCACHE_PENDING_DIR="${WALLCACHE_QUEUE_ROOT}/pending"
WALLCACHE_RUNNING_DIR="${WALLCACHE_QUEUE_ROOT}/running"
WALLCACHE_PID_FILE="${WALLCACHE_QUEUE_ROOT}/daemon.pid"
WALLCACHE_LOCK_FILE="${WALLCACHE_QUEUE_ROOT}/daemon.lock"

WALLCACHE_DEFAULT_BATCH_MAX=128
WALLCACHE_DEFAULT_IDLE_TIMEOUT=120

[[ "${WALLCACHE_BATCH_MAX:-}" =~ ^[0-9]+$ ]] || WALLCACHE_BATCH_MAX="${WALLCACHE_DEFAULT_BATCH_MAX}"
[[ "${WALLCACHE_IDLE_TIMEOUT:-}" =~ ^[0-9]+$ ]] || WALLCACHE_IDLE_TIMEOUT="${WALLCACHE_DEFAULT_IDLE_TIMEOUT}"
(( WALLCACHE_BATCH_MAX < 1 )) && WALLCACHE_BATCH_MAX=1
(( WALLCACHE_IDLE_TIMEOUT < 1 )) && WALLCACHE_IDLE_TIMEOUT="${WALLCACHE_DEFAULT_IDLE_TIMEOUT}"

wallcache_wake_fd=""

source "${HYPR_LIB_DIR}/wallpaper/cache/queue.bash" || exit 1
source "${HYPR_LIB_DIR}/wallpaper/cache/daemon.bash" || exit 1

wallcache_show_help() {
  cat <<EOF
Usage: hyprshell wallpaper/wallcache.daemon [mode] [options]

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
  WALLCACHE_BATCH_MAX     Max jobs per daemon batch (default: ${WALLCACHE_DEFAULT_BATCH_MAX})
  WALLCACHE_IDLE_TIMEOUT  Daemon idle exit timeout seconds (default: ${WALLCACHE_DEFAULT_IDLE_TIMEOUT})
EOF
}

wallcache_main() {
  local mode="enqueue" wall="" theme="" enqueue_failed=0
  local -a enqueue_walls=() enqueue_themes=()

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
        wallcache_show_help
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        wallcache_show_help >&2
        exit 1
        ;;
    esac
  done

  case "${mode}" in
    run)
      wallcache_run_daemon
      ;;
    start)
      wallcache_start_daemon
      ;;
    stop)
      wallcache_stop_daemon
      ;;
    status)
      wallcache_prepare_queue_directories
      wallcache_print_status
      ;;
    enqueue)
      wallcache_prepare_queue_directories
      for theme in "${enqueue_themes[@]}"; do
        wallcache_enqueue_theme "${theme}" || enqueue_failed=1
      done
      for wall in "${enqueue_walls[@]}"; do
        wallcache_enqueue_wallpaper "${wall}" || enqueue_failed=1
      done
      wallcache_wake_daemon >/dev/null 2>&1 || wallcache_start_daemon >/dev/null 2>&1 || return
      return "${enqueue_failed}"
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" != "$0" ]] || wallcache_main "$@"
