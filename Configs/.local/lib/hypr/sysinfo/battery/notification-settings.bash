suppress_status_notifications=${BATTERY_NOTIFY_DOCK:-false}
full_threshold_percent=${BATTERY_NOTIFY_THRESHOLD_FULL:-100}
critical_threshold_percent=${BATTERY_NOTIFY_THRESHOLD_CRITICAL:-5}
unplug_threshold_percent=${BATTERY_NOTIFY_THRESHOLD_UNPLUG:-80}
low_threshold_percent=${BATTERY_NOTIFY_THRESHOLD_LOW:-20}
critical_grace_seconds=${BATTERY_NOTIFY_TIMER:-120}
full_reminder_interval_minutes=${BATTERY_NOTIFY_NOTIFY:-1140}
notification_step_percent=${BATTERY_NOTIFY_INTERVAL:-5}
critical_command=${BATTERY_NOTIFY_EXECUTE_CRITICAL:-"hyprshell session/suspend.sh"}
low_command=${BATTERY_NOTIFY_EXECUTE_LOW:-}
unplug_command=${BATTERY_NOTIFY_EXECUTE_UNPLUG:-}
charging_command=${BATTERY_NOTIFY_EXECUTE_CHARGING:-}
discharging_command=${BATTERY_NOTIFY_EXECUTE_DISCHARGING:-}

battery_print_notification_settings() {
  cat <<EOF

Set BATTERY_NOTIFY_* overrides in '$XDG_STATE_HOME/hypr/env-overrides'.

      STATUS      THRESHOLD    INTERVAL
      Full        $full_threshold_percent          $full_reminder_interval_minutes Minutes
      Critical    $critical_threshold_percent           $critical_grace_seconds Seconds then '$critical_command'
      Low         $low_threshold_percent           $notification_step_percent Percent    then '$low_command'
      Unplug      $unplug_threshold_percent          $notification_step_percent Percent   then '$unplug_command'

      Command on Charging: $charging_command
      Command on Discharging: $discharging_command
      Dock Mode: $suppress_status_notifications (Will not notify on status change) 


EOF
}

battery_warn_outside_range() {
  local value=$1 min=$2 max=$3 label=$4
  [[ $value =~ ^[0-9]+$ ]] && ((value >= min && value <= max)) ||
    printf '%s WARNING: %s must be %s - %s.\n' "$value" "$label" "$min" "$max" >&2
}

battery_check_notification_settings() {
battery_warn_outside_range "$full_threshold_percent" 50 100 "Full Threshold"
battery_warn_outside_range "$critical_threshold_percent" 2 50 "Critical Threshold"
battery_warn_outside_range "$low_threshold_percent" 10 80 "Low Threshold"
battery_warn_outside_range "$unplug_threshold_percent" 40 100 "Unplug Threshold"
battery_warn_outside_range "$critical_grace_seconds" 60 1000 "Timer"
battery_warn_outside_range "$full_reminder_interval_minutes" 1 1140 "Notify"
battery_warn_outside_range "$notification_step_percent" 1 10 "Interval"
}
