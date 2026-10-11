SECONDS_PER_MINUTE=60
BATTERY_ICON_PERCENT_STEP=10
CRITICAL_MIN_GRACE_SECONDS=60

battery_icon_level_into() {
  printf -v "$1" "$2" "$(((battery_percent + BATTERY_ICON_PERCENT_STEP / 2) / BATTERY_ICON_PERCENT_STEP * BATTERY_ICON_PERCENT_STEP))"
}

battery_run_command() {
  local command_string="$1" run_mode="${2:-sync}"
  [[ -n "${command_string//[[:space:]]/}" ]] || return 0
  if [[ "$run_mode" == background ]]; then
    nohup python3 "${sysinfo_dir}/battery/run-command.py" "$command_string" &>/dev/null &
  else
    python3 "${sysinfo_dir}/battery/run-command.py" "$command_string"
  fi
}

battery_update_critical_deadline() {
  if ((battery_percent > critical_threshold_percent)) || [[ "$battery_status" != Discharging ]]; then
    critical_deadline_seconds=0 critical_action_executed=false
  elif ((critical_deadline_seconds == 0)) && ! "$critical_action_executed"; then
    local grace_seconds=$critical_grace_seconds
    ((grace_seconds >= CRITICAL_MIN_GRACE_SECONDS)) || grace_seconds=$CRITICAL_MIN_GRACE_SECONDS
    critical_deadline_seconds=$((SECONDS + grace_seconds))
    dunstify -a Power -t "$NOTIFY_STICKY_MS" -r "$NOTIFY_ID_BATTERY" -u CRITICAL \
      -i xfce4-battery-critical "Battery Critically Low" \
      "$battery_percent% is critically low. Device will execute $critical_command in $(printf '%d:%02d' "$((grace_seconds / SECONDS_PER_MINUTE))" "$((grace_seconds % SECONDS_PER_MINUTE))")."
  fi
}

battery_run_critical_action() {
  battery_refresh_state || return 1
  battery_update_critical_deadline
  ((critical_deadline_seconds > 0)) || return 0
  battery_run_command "$critical_command" background
  critical_deadline_seconds=0 critical_action_executed=true
}

battery_notify_thresholds() {
  local battery_icon_level
  if [[ "$battery_percent" -ge "$unplug_threshold_percent" ]] && [[ "$battery_status" != "Discharging" ]] && [[ "$battery_status" != "Full" ]] && (((battery_percent - last_notified_percent) >= notification_step_percent)); then
    battery_icon_level_into battery_icon_level '%03d'
    if $verbose_enabled; then echo "Prompt:UNPLUG: $unplug_threshold_percent $battery_status $battery_percent $battery_icon_level"; fi
    dunstify -a "Power" -t "${NOTIFY_LONG_MS}" -r "${NOTIFY_ID_BATTERY}" -u "CRITICAL" -i "battery-${battery_icon_level:-100}-charging" "Battery Charged" "Battery is at $battery_percent%. You can unplug the charger"
    last_notified_percent=$battery_percent
  elif [[ "$battery_percent" -le "$critical_threshold_percent" && "$battery_status" == Discharging ]]; then
    return 0
  elif [[ "$battery_percent" -le "$low_threshold_percent" ]] && [[ "$battery_status" == "Discharging" ]] && (((last_notified_percent - battery_percent) >= notification_step_percent)); then
    battery_icon_level_into battery_icon_level '%d'
    if $verbose_enabled; then echo "Prompt:LOW: $low_threshold_percent $battery_status $battery_percent"; fi
    dunstify -a "Power" -t "${NOTIFY_STICKY_MS}" -r "${NOTIFY_ID_BATTERY}" -u "CRITICAL" -i "battery-level-${battery_icon_level:-10}-symbolic" "Battery Low" "Battery is at $battery_percent%. Connect the charger."
    last_notified_percent=$battery_percent
  fi
}

battery_notify_status_change() {
  local battery_icon_level urgency
  case "$battery_status" in
    "Discharging")
      if $verbose_enabled; then echo "Case:$battery_status Level: $battery_percent"; fi
      if [[ "$last_notified_status" != "Discharging" ]]; then
        last_notified_status=$battery_status
        urgency=NORMAL
        [[ $battery_percent -le $low_threshold_percent ]] && urgency=CRITICAL
        battery_icon_level_into battery_icon_level '%d'
        dunstify -a "Power" -t "${NOTIFY_MS}" -r "${NOTIFY_ID_BATTERY}" -u "${urgency:-normal}" -i "battery-level-${battery_icon_level:-10}-symbolic" "Charger Plug Out" "Battery is at $battery_percent%."
        battery_run_command "${discharging_command}"
      fi
      ;;
    "Not"* | "Charging")
      if $verbose_enabled; then echo "Case:$battery_status Level: $battery_percent"; fi
      if [[ "$last_notified_status" == "Discharging" ]] || [[ "$last_notified_status" == "Not"* ]]; then
        last_notified_status=$battery_status
        urgency=NORMAL
        [[ $battery_percent -ge $unplug_threshold_percent ]] && urgency=CRITICAL
        battery_icon_level_into battery_icon_level '%03d'
        dunstify -a "Power" -t "${NOTIFY_MS}" -r "${NOTIFY_ID_BATTERY}" -u "${urgency:-normal}" -i "battery-${battery_icon_level:-100}-charging" "Charger Plug In" "Battery is at $battery_percent%."
        battery_run_command "${charging_command}"
      fi
      ;;
    "Full")
      if $verbose_enabled; then echo "Case:$battery_status Level: $battery_percent"; fi
      if [[ $battery_status != "Discharging" ]]; then
        local now=${EPOCHSECONDS}
        if [[ "$last_notified_status" == *"harging"* ]] || ((now - last_full_notification_epoch >= $((full_reminder_interval_minutes * SECONDS_PER_MINUTE)))); then
          dunstify -a "Power" -t "${NOTIFY_LONG_MS}" -r "${NOTIFY_ID_BATTERY}" -u "CRITICAL" -i "battery-full-charging-symbolic" "Battery Full" "Please unplug your Charger"
          last_notified_status=$battery_status
          last_full_notification_epoch=$now
          battery_run_command "${charging_command}"
        fi
      fi
      ;;
    *)
      if [[ -z "${reported_unknown_statuses[$battery_status]:-}" ]]; then
        printf 'Unknown battery status: %s\n' "$battery_status" >&2
        reported_unknown_statuses["$battery_status"]=1
      fi
      ;;
  esac
}
