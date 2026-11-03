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
  local -n monitor_ref=$1
  battery_refresh_state || return

  if [ "$battery_status" != "${monitor_ref[last_battery_status]}" ] || [ "$battery_percent" != "${monitor_ref[last_battery_percent]}" ]; then
    monitor_ref[last_battery_status]=$battery_status
    monitor_ref[last_battery_percent]=$battery_percent
    battery_print_verbose_state

    if [[ "$battery_percent" -le "$low_threshold_percent" ]]; then
      battery_run_command "${low_command}"
    fi
    if [[ "$battery_percent" -ge "$unplug_threshold_percent" ]]; then
      battery_run_command "${unplug_command}"
    fi
    if ! $suppress_status_notifications; then battery_notify_status_change "$1"; fi
    battery_notify_thresholds "$1"
  fi
  battery_update_critical_deadline "$1"
}

battery_stop_monitor() {
  local monitor_pid=$1 event_fd=$2
  kill "$monitor_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
  exec {event_fd}<&-
}

battery_monitor_events() {
  local battery_event_fd battery_monitor_pid event deadline_seconds remaining_seconds read_status monitor_status=0
  local -A battery_monitor=(
    [last_battery_status]=$battery_status [last_battery_percent]=$battery_percent
    [last_notified_percent]=$battery_percent [last_notified_status]=$battery_status
    [last_full_notification_epoch]=0 [critical_deadline_seconds]=0 [critical_action_executed]=false
  )
  exec {battery_event_fd}< <(exec upower --monitor)
  battery_monitor_pid=$!
  trap "battery_stop_monitor $battery_monitor_pid $battery_event_fd" EXIT
  trap 'exit 0' INT TERM
  battery_update_critical_deadline battery_monitor
  while true; do
    deadline_seconds=${battery_monitor[critical_deadline_seconds]}
    remaining_seconds=$((deadline_seconds - SECONDS))
    if ((deadline_seconds > 0 && remaining_seconds <= 0)); then
      battery_run_critical_action battery_monitor || { monitor_status=$?; break; }
      continue
    fi
    local -a read_options=(-r -u "$battery_event_fd")
    ((deadline_seconds == 0)) || read_options+=(-t "$remaining_seconds")
    if IFS= read "${read_options[@]}" event; then
      [[ "$event" != *"/battery_BAT"* ]] || battery_process_state_change battery_monitor || { monitor_status=$?; break; }
    else
      read_status=$?
      ((read_status > 128 && deadline_seconds > 0)) && continue
      wait "$battery_monitor_pid" 2>/dev/null || monitor_status=$?
      break
    fi
  done
  battery_stop_monitor "$battery_monitor_pid" "$battery_event_fd"
  trap - EXIT INT TERM
  return "${monitor_status}"
}
