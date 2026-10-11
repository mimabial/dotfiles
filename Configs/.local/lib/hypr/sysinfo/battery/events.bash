battery_print_verbose_state() {
  if $verbose_enabled; then
    cat <<VERBOSE
=============================================
        Battery Status: $battery_status
        Battery Percentage: $battery_percent
=============================================
VERBOSE
  fi
}

battery_process_state_change() {
  battery_refresh_state || return

  if [ "$battery_status" != "$last_battery_status" ] || [ "$battery_percent" != "$last_battery_percent" ]; then
    last_battery_status=$battery_status
    last_battery_percent=$battery_percent
    battery_print_verbose_state

    if [[ "$battery_percent" -le "$low_threshold_percent" ]]; then
      battery_run_command "${low_command}"
    fi
    if [[ "$battery_percent" -ge "$unplug_threshold_percent" ]]; then
      battery_run_command "${unplug_command}"
    fi
    if ! $suppress_status_notifications; then battery_notify_status_change; fi
    battery_notify_thresholds
  fi
  battery_update_critical_deadline
}

battery_stop_monitor() {
  kill "$battery_monitor_pid" 2>/dev/null || true
  wait "$battery_monitor_pid" 2>/dev/null || true
  exec {battery_event_fd}<&-
}

battery_monitor_events() {
  local battery_event_fd battery_monitor_pid event remaining_seconds read_status monitor_status=0
  local last_battery_status=$battery_status last_battery_percent=$battery_percent
  local last_notified_percent=$battery_percent last_notified_status=$battery_status
  local last_full_notification_epoch=0 critical_deadline_seconds=0 critical_action_executed=false
  local -A reported_unknown_statuses=()
  exec {battery_event_fd}< <(exec upower --monitor)
  battery_monitor_pid=$!
  trap battery_stop_monitor EXIT
  trap 'exit 0' INT TERM
  battery_update_critical_deadline
  while true; do
    remaining_seconds=$((critical_deadline_seconds - SECONDS))
    if ((critical_deadline_seconds > 0 && remaining_seconds <= 0)); then
      battery_run_critical_action || { monitor_status=$?; break; }
      continue
    fi
    local -a read_options=(-r -u "$battery_event_fd")
    ((critical_deadline_seconds == 0)) || read_options+=(-t "$remaining_seconds")
    if IFS= read "${read_options[@]}" event; then
      [[ "$event" != *"/battery_BAT"* ]] || battery_process_state_change || { monitor_status=$?; break; }
    else
      read_status=$?
      ((read_status > 128 && critical_deadline_seconds > 0)) && continue
      wait "$battery_monitor_pid" 2>/dev/null || monitor_status=$?
      break
    fi
  done
  battery_stop_monitor
  trap - EXIT INT TERM
  return "${monitor_status}"
}
