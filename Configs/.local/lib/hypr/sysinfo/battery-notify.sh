#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
hypr_runtime_load_state || exit 1
dock_mode_enabled=${BATTERY_NOTIFY_DOCK:-false}

print_battery_notification_config() {
  cat <<EOF

Set BATTERY_NOTIFY_* overrides in '$XDG_STATE_HOME/hypr/env-overrides'.

      STATUS      THRESHOLD    INTERVAL
      Full        $battery_full_threshold          $full_notification_interval_minutes Minutes
      Critical    $battery_critical_threshold           $critical_countdown_seconds Seconds then '$execute_critical'
      Low         $battery_low_threshold           $notification_percentage_step Percent    then '$execute_low'
      Unplug      $unplug_charger_threshold          $notification_percentage_step Percent   then '$execute_unplug'

      Command on Charging: $execute_charging
      Command on Discharging: $execute_discharging
      Dock Mode: $dock_mode_enabled (Will not notify on status change) 


EOF
}

exit_when_battery_missing() {
  if grep -q "Battery" /sys/class/power_supply/BAT*/type; then
    return 0
  else
    echo "No battery detected. If you think this is an error please post a report to the repo"
    exit 0
  fi
}
exit_when_battery_missing
print_verbose_state() {
  if $verbose; then
    cat <<VERBOSE
=============================================
        Battery Status: $battery_status
        Battery Percentage: $battery_percentage
=============================================
VERBOSE
  fi
}

parse_command_args() {
  local command_string="$1"

  python3 - "$command_string" <<'PY'
import shlex
import sys

try:
    args = shlex.split(sys.argv[1], posix=True)
except ValueError as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(1)

for arg in args:
    sys.stdout.buffer.write(arg.encode("utf-8"))
    sys.stdout.buffer.write(b"\0")
PY
}

run_configured_command() {
  local command_string="$1"
  local run_mode="${2:-sync}"
  local -a command_args=()

  [[ -n "${command_string//[[:space:]]/}" ]] || return 0

  if ! mapfile -d '' -t command_args < <(parse_command_args "${command_string}"); then
    echo "Warning: failed to parse command: ${command_string}" >&2
    return 1
  fi

  ((${#command_args[@]} > 0)) || return 0

  case "${run_mode}" in
    background)
      nohup "${command_args[@]}" &>/dev/null &
      ;;
    *)
      "${command_args[@]}"
      ;;
  esac
}

notify_battery_thresholds() {
  if [[ "$battery_percentage" -ge "$unplug_charger_threshold" ]] && [[ "$battery_status" != "Discharging" ]] && [[ "$battery_status" != "Full" ]] && (((battery_percentage - last_notified_percentage) >= notification_percentage_step)); then
    printf -v battery_icon_level '%03d' "$(((battery_percentage + 5) / 10 * 10))"
    if $verbose; then echo "Prompt:UNPLUG: $unplug_charger_threshold $battery_status $battery_percentage $battery_icon_level"; fi
    dunstify -a "Power" -t 5000 -r 5 -u "CRITICAL" -i "battery-${battery_icon_level:-100}-charging" "Battery Charged" "Battery is at $battery_percentage%. You can unplug the charger"
    last_notified_percentage=$battery_percentage
  elif [[ "$battery_percentage" -le "$battery_critical_threshold" ]]; then
    seconds_remaining=$((critical_countdown_seconds > 60 ? critical_countdown_seconds : 60))
    while [ $seconds_remaining -gt 0 ] && [[ $battery_status == "Discharging"* ]]; do
      for battery in /sys/class/power_supply/BAT*; do battery_status=$(<"$battery/status"); done
      if [[ $battery_status != "Discharging" ]]; then break; fi
      dunstify -a "Power" -t 0 -r 5 -u "CRITICAL" -i "xfce4-battery-critical" "Battery Critically Low" "$battery_percentage% is critically low. Device will execute $execute_critical in $((seconds_remaining / 60)):$((seconds_remaining % 60)) ."
      seconds_remaining=$((seconds_remaining - 1))
      sleep 1
    done
    [ $seconds_remaining -eq 0 ] && run_critical_action
  elif [[ "$battery_percentage" -le "$battery_low_threshold" ]] && [[ "$battery_status" == "Discharging" ]] && (((last_notified_percentage - battery_percentage) >= notification_percentage_step)); then
    printf -v battery_icon_level '%d' "$(((battery_percentage + 5) / 10 * 10))"
    if $verbose; then echo "Prompt:LOW: $battery_low_threshold $battery_status $battery_percentage"; fi
    dunstify -a "Power" -t 0 -r 5 -u "CRITICAL" -i "battery-level-${battery_icon_level:-10}-symbolic" "Battery Low" "Battery is at $battery_percentage%. Connect the charger."
    last_notified_percentage=$battery_percentage
  fi
}

run_critical_action() {
  run_configured_command "${execute_critical}" background
}

handle_battery_status_transition() {
  if [[ $battery_percentage -ge $battery_full_threshold ]] && [[ "$battery_status" != *"Discharging"* ]]; then
    echo "Full and $battery_status"
    battery_status="Full"
  fi
  case "$battery_status" in
    "Discharging")
      if $verbose; then echo "Case:$battery_status Level: $battery_percentage"; fi
      if [[ "$previous_notified_status" != "Discharging" ]] || [[ "$previous_notified_status" == "Full" ]]; then
        previous_notified_status=$battery_status
        urgency=NORMAL
        [[ $battery_percentage -le $battery_low_threshold ]] && urgency=CRITICAL
        printf -v battery_icon_level '%d' "$(((battery_percentage + 5) / 10 * 10))"
        dunstify -a "Power" -t 3000 -r 5 -u "${urgency:-normal}" -i "battery-level-${battery_icon_level:-10}-symbolic" "Charger Plug Out" "Battery is at $battery_percentage%."
        run_configured_command "${execute_discharging}"
      fi
      notify_battery_thresholds
      ;;
    "Not"* | "Charging")
      if $verbose; then echo "Case:$battery_status Level: $battery_percentage"; fi
      if [[ "$previous_notified_status" == "Discharging" ]] || [[ "$previous_notified_status" == "Not"* ]]; then
        previous_notified_status=$battery_status
        urgency=NORMAL
        [[ $battery_percentage -ge $unplug_charger_threshold ]] && urgency=CRITICAL
        printf -v battery_icon_level '%03d' "$(((battery_percentage + 5) / 10 * 10))"
        dunstify -a "Power" -t 3000 -r 5 -u "${urgency:-normal}" -i "battery-${battery_icon_level:-100}-charging" "Charger Plug In" "Battery is at $battery_percentage%."
        run_configured_command "${execute_charging}"
      fi
      notify_battery_thresholds
      ;;
    "Full")
      if $verbose; then echo "Case:$battery_status Level: $battery_percentage"; fi
      if [[ $battery_status != "Discharging" ]]; then
        local now
        now=$(date +%s)
        if [[ "$previous_notified_status" == *"harging"* ]] || ((now - last_full_notification_time >= $((full_notification_interval_minutes * 60)))); then
          dunstify -a "Power" -t 5000 -r 5 -u "CRITICAL" -i "battery-full-charging-symbolic" "Battery Full" "Please unplug your Charger"
          previous_notified_status=$battery_status
          last_full_notification_time=$now
          run_configured_command "${execute_charging}"
        fi
      fi
      ;;
    *)
      if [[ ! -f "${TMPDIR:-/tmp}/battery.notify.status.fallback.$battery_status-$$" ]]; then
        echo "Status: '==>> \"${battery_status}\" <<==' Script on Fallback mode,Unknown power supply status.Please copy this line and raise an issue to the Github Repo.Also run 'ls ${TMPDIR:-/tmp}/battery.notify' to see the list of lock files.*"
        touch "${TMPDIR:-/tmp}/battery.notify.status.fallback.$battery_status-$$"
      fi
      notify_battery_thresholds
      ;;
  esac
}

get_battery_percentage() {
  local battery=$1
  local percent=""

  if [[ -r "$battery/capacity" ]]; then
    percent=$(<"$battery/capacity")
  elif [[ -r "$battery/energy_now" && -r "$battery/energy_full" ]]; then
    local energy_now energy_full
    energy_now=$(<"$battery/energy_now")
    energy_full=$(<"$battery/energy_full")
    if [[ "$energy_full" =~ ^[0-9]+$ ]] && ((energy_full > 0)); then
      percent=$((energy_now * 100 / energy_full))
    fi
  elif [[ -r "$battery/charge_now" && -r "$battery/charge_full" ]]; then
    local charge_now charge_full
    charge_now=$(<"$battery/charge_now")
    charge_full=$(<"$battery/charge_full")
    if [[ "$charge_full" =~ ^[0-9]+$ ]] && ((charge_full > 0)); then
      percent=$((charge_now * 100 / charge_full))
    fi
  elif [[ -r "$battery/uevent" ]]; then
    percent=$(awk -F= '/^POWER_SUPPLY_CAPACITY=/{print $2}' "$battery/uevent")
  fi

  if [[ "$percent" =~ ^[0-9]+$ ]]; then
    echo "$percent"
  fi
}

refresh_battery_state() {
  total_percentage=0 battery_count=0
  for battery in /sys/class/power_supply/BAT*; do
    [[ -r "$battery/status" ]] || continue
    battery_status=$(<"$battery/status")
    battery_percentage=$(get_battery_percentage "$battery")
    if [[ -z "$battery_percentage" ]]; then
      continue
    fi
    total_percentage=$((total_percentage + battery_percentage))
    battery_count=$((battery_count + 1))
  done
  if ((battery_count == 0)); then
    echo "Battery capacity unavailable. Exiting battery notify." >&2
    exit 0
  fi
  battery_percentage=$((total_percentage / battery_count))
}

process_battery_state_change() {
  refresh_battery_state

  if [ "$battery_status" != "$last_battery_status" ] || [ "$battery_percentage" != "$last_battery_percentage" ]; then
    last_battery_status=$battery_status
    last_battery_percentage=$battery_percentage
    print_verbose_state
    notify_battery_thresholds

    if [[ "$battery_percentage" -le "$battery_low_threshold" ]]; then
      run_configured_command "${execute_low}"
    fi
    if [[ "$battery_percentage" -ge "$unplug_charger_threshold" ]]; then
      run_configured_command "${execute_unplug}"
    fi
    if ! $dock_mode_enabled; then handle_battery_status_transition; fi
  fi
}

battery_full_threshold=${BATTERY_NOTIFY_THRESHOLD_FULL:-100}
battery_critical_threshold=${BATTERY_NOTIFY_THRESHOLD_CRITICAL:-5}
unplug_charger_threshold=${BATTERY_NOTIFY_THRESHOLD_UNPLUG:-80}
battery_low_threshold=${BATTERY_NOTIFY_THRESHOLD_LOW:-20}
critical_countdown_seconds=${BATTERY_NOTIFY_TIMER:-120}
full_notification_interval_minutes=${BATTERY_NOTIFY_NOTIFY:-1140}
notification_percentage_step=${BATTERY_NOTIFY_INTERVAL:-5}
execute_critical=${BATTERY_NOTIFY_EXECUTE_CRITICAL:-"hyprshell session/suspend.sh"}
execute_low=${BATTERY_NOTIFY_EXECUTE_LOW:-}
execute_unplug=${BATTERY_NOTIFY_EXECUTE_UNPLUG:-}
execute_charging=${BATTERY_NOTIFY_EXECUTE_CHARGING:-}
execute_discharging=${BATTERY_NOTIFY_EXECUTE_DISCHARGING:-}

main() {
  trap 'find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -name "battery.notify.status.fallback.*-$$" -delete 2>/dev/null || true' EXIT

  print_battery_notification_config
  if $verbose; then
    for line in "Verbose Mode is ON..." "" "" "" ""; do echo "${line}"; done
  fi
  refresh_battery_state
  last_notified_percentage=$battery_percentage
  previous_notified_status=$battery_status
  last_full_notification_time=0
  local battery_path=""
  battery_path="$(upower -e | grep battery || true)"
  [[ -n "${battery_path}" ]] || return 0
  dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',path='${battery_path}'" 2>/dev/null | while read -r property_change_signal; do process_battery_state_change; done
}

verbose=false
case "${1:-}" in
  -i | --info)
    print_battery_notification_config
    exit 0
    ;;
  -v | --verbose)
    verbose=true
    ;;
  -*)
    cat <<HELP
Usage: $0 [options]

[-i|--info]                    Display configuration information
[-v|--verbose]                 Debugging mode
[-h|--help]                 This Message
HELP
    exit 0
    ;;
esac

warn_if_outside_range() {
  local value=$1 min=$2 max=$3 label=$4
  [[ $value =~ ^[0-9]+$ ]] && ((value >= min && value <= max)) ||
    printf '%s WARNING: %s must be %s - %s.\n' "$value" "$label" "$min" "$max" >&2
}

warn_if_outside_range "$battery_full_threshold" 50 100 "Full Threshold"
warn_if_outside_range "$battery_critical_threshold" 2 50 "Critical Threshold"
warn_if_outside_range "$battery_low_threshold" 10 80 "Low Threshold"
warn_if_outside_range "$unplug_charger_threshold" 40 100 "Unplug Threshold"
warn_if_outside_range "$critical_countdown_seconds" 60 1000 "Timer"
warn_if_outside_range "$full_notification_interval_minutes" 1 1140 "Notify"
warn_if_outside_range "$notification_percentage_step" 1 10 "Interval"

main
