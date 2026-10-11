IDLE_MANAGER_SERVICE=hyprland-idle-manager.service
IDLE_DAEMON_SERVICE=hyprland-hypridle
IDLE_DAEMON_PID=""

idle_ensure_manager_running() {
  hypr_svc_user start "${IDLE_MANAGER_SERVICE}"
}

idle_notify_manager() {
  local manager_script="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/session/idle-manager.sh"

  local signalled=0

  if hypr_svc_user is-active "${IDLE_MANAGER_SERVICE}"; then
    hypr_svc_user_signal "${IDLE_MANAGER_SERVICE}" USR1
    return
  fi

  while IFS= read -r pid; do
    kill -USR1 "${pid}" 2>/dev/null && signalled=1
  done < <(hypr_user_pgrep -f "${manager_script}" 2>/dev/null || true)
  ((signalled))
}

idle_daemon_is_active() {
  hypr_svc_user is-active "${IDLE_DAEMON_SERVICE}" || hypr_user_pgrep -x hypridle >/dev/null 2>&1
}

idle_start_daemon() {
  idle_daemon_is_active && return 0
  hypr_svc_user restart "${IDLE_DAEMON_SERVICE}" && return 0
  command -v hypridle >/dev/null 2>&1 || return 1
  hypridle >/dev/null 2>&1 &
  IDLE_DAEMON_PID=$!
}

idle_stop_daemon() {
  local stop_status=0 pkill_status=0

  "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/power-manager.sh" idle-cancel || stop_status=$?
  if hypr_svc_user is-active "${IDLE_DAEMON_SERVICE}"; then
    hypr_svc_user stop "${IDLE_DAEMON_SERVICE}" || stop_status=$?
  else
    hypr_user_pkill -x hypridle >/dev/null 2>&1 || pkill_status=$?
    ((pkill_status == 0 || pkill_status == PROCPS_NO_MATCH_STATUS)) || stop_status="${pkill_status}"
  fi
  if [[ -n "${IDLE_DAEMON_PID}" ]]; then
    wait "${IDLE_DAEMON_PID}" 2>/dev/null || true
    IDLE_DAEMON_PID=""
  fi
  return "${stop_status}"
}
