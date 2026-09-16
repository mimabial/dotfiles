#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

usage='Usage: hyprshell system/monitor-profile {start|manage|unmanage|restart|service-enabled|service-active}'
hypr_help_guard "${usage}" "$@"

service_enabled() {
  hyprmoncfg doctor >/dev/null 2>&1
}

service_active() {
  pgrep -x hyprmoncfgd >/dev/null 2>&1
}

start_daemon() {
  local log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
  command -v hyprmoncfgd >/dev/null 2>&1 || return 1
  service_active && return 0
  mkdir -p "${log_dir}"
  hyprshell app -t service -- hyprmoncfgd >>"${log_dir}/hyprmoncfgd.log" 2>&1
}

case "${1:-}" in
  start) start_daemon ;;
  manage)
    hyprmoncfg manage
    start_daemon
    ;;
  unmanage)
    hyprmoncfg unmanage
    ;;
  restart)
    pkill -TERM -x hyprmoncfgd && timeout 1 pidwait -x hyprmoncfgd || true
    start_daemon
    ;;
  service-enabled) service_enabled ;;
  service-active) service_active ;;
  *) printf '%s\n' "${usage}" >&2; exit 2 ;;
esac
