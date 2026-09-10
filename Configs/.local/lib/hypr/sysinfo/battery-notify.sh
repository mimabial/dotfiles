#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
hypr_runtime_load_state || exit 1
dock=${BATTERY_NOTIFY_DOCK:-false}

config_info() {
  cat <<EOF

Set BATTERY_NOTIFY_* overrides in '$XDG_STATE_HOME/hypr/env-overrides'.

      STATUS      THRESHOLD    INTERVAL
      Full        $battery_full_threshold          $notify Minutes
      Critical    $battery_critical_threshold           $timer Seconds then '$execute_critical'
      Low         $battery_low_threshold           $interval Percent    then '$execute_low'
      Unplug      $unplug_charger_threshold          $interval Percent   then '$execute_unplug'

      Command on Charging: $execute_charging
      Command on Discharging: $execute_discharging
      Dock Mode: $dock (Will not notify on status change) 


EOF
}

is_laptop() {
  if grep -q "Battery" /sys/class/power_supply/BAT*/type; then
    return 0
  else
    echo "No battery detected. If you think this is an error please post a report to the repo"
    exit 0
  fi
}
is_laptop
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

notify_thresholds() {
  if [[ "$battery_percentage" -ge "$unplug_charger_threshold" ]] && [[ "$battery_status" != "Discharging" ]] && [[ "$battery_status" != "Full" ]] && (((battery_percentage - last_notified_percentage) >= interval)); then
    printf -v steps '%03d' "$(((battery_percentage + 5) / 10 * 10))"
    if $verbose; then echo "Prompt:UNPLUG: $unplug_charger_threshold $battery_status $battery_percentage $steps"; fi
    dunstify -a "Power" -t 5000 -r 5 -u "CRITICAL" -i "battery-${steps:-100}-charging" "Battery Charged" "Battery is at $battery_percentage%. You can unplug the charger"
    last_notified_percentage=$battery_percentage
  elif [[ "$battery_percentage" -le "$battery_critical_threshold" ]]; then
    count=$((timer > 60 ? timer : 60))
    while [ $count -gt 0 ] && [[ $battery_status == "Discharging"* ]]; do
      for battery in /sys/class/power_supply/BAT*; do battery_status=$(<"$battery/status"); done
      if [[ $battery_status != "Discharging" ]]; then break; fi
      dunstify -a "Power" -t 0 -r 5 -u "CRITICAL" -i "xfce4-battery-critical" "Battery Critically Low" "$battery_percentage% is critically low. Device will execute $execute_critical in $((count / 60)):$((count % 60)) ."
      count=$((count - 1))
      sleep 1
    done
    [ $count -eq 0 ] && run_critical_action
  elif [[ "$battery_percentage" -le "$battery_low_threshold" ]] && [[ "$battery_status" == "Discharging" ]] && (((last_notified_percentage - battery_percentage) >= interval)); then
    printf -v steps '%d' "$(((battery_percentage + 5) / 10 * 10))"
    if $verbose; then echo "Prompt:LOW: $battery_low_threshold $battery_status $battery_percentage"; fi
    dunstify -a "Power" -t 0 -r 5 -u "CRITICAL" -i "battery-level-${steps:-10}-symbolic" "Battery Low" "Battery is at $battery_percentage%. Connect the charger."
    last_notified_percentage=$battery_percentage
  fi
}

run_critical_action() {
  run_configured_command "${execute_critical}" background
}

resolve_battery_status() {
  if [[ $battery_percentage -ge $battery_full_threshold ]] && [[ "$battery_status" != *"Discharging"* ]]; then
    echo "Full and $battery_status"
    battery_status="Full"
  fi
  case "$battery_status" in
    "Discharging")
      if $verbose; then echo "Case:$battery_status Level: $battery_percentage"; fi
      if [[ "$prev_status" != "Discharging" ]] || [[ "$prev_status" == "Full" ]]; then
        prev_status=$battery_status
        urgency=NORMAL
        [[ $battery_percentage -le $battery_low_threshold ]] && urgency=CRITICAL
        printf -v steps '%d' "$(((battery_percentage + 5) / 10 * 10))"
        dunstify -a "Power" -t 3000 -r 5 -u "${urgency:-normal}" -i "battery-level-${steps:-10}-symbolic" "Charger Plug Out" "Battery is at $battery_percentage%."
        run_configured_command "${execute_discharging}"
      fi
      notify_thresholds
      ;;
    "Not"* | "Charging")
      if $verbose; then echo "Case:$battery_status Level: $battery_percentage"; fi
      if [[ "$prev_status" == "Discharging" ]] || [[ "$prev_status" == "Not"* ]]; then
        prev_status=$battery_status
        count=$((timer > 60 ? timer : 60))
        urgency=NORMAL
        [[ $battery_percentage -ge $unplug_charger_threshold ]] && urgency=CRITICAL
        printf -v steps '%03d' "$(((battery_percentage + 5) / 10 * 10))"
        dunstify -a "Power" -t 3000 -r 5 -u "${urgency:-normal}" -i "battery-${steps:-100}-charging" "Charger Plug In" "Battery is at $battery_percentage%."
        run_configured_command "${execute_charging}"
      fi
      notify_thresholds
      ;;
    "Full")
      if $verbose; then echo "Case:$battery_status Level: $battery_percentage"; fi
      if [[ $battery_status != "Discharging" ]]; then
        local now
        now=$(date +%s)
        if [[ "$prev_status" == *"harging"* ]] || ((now - last_full_notify_ts >= $((notify * 60)))); then
          dunstify -a "Power" -t 5000 -r 5 -u "CRITICAL" -i "battery-full-charging-symbolic" "Battery Full" "Please unplug your Charger"
          prev_status=$battery_status
          last_full_notify_ts=$now
          run_configured_command "${execute_charging}"
        fi
      fi
      ;;
    *)
      if [[ ! -f "${TMPDIR:-/tmp}/battery.notify.status.fallback.$battery_status-$$" ]]; then
        echo "Status: '==>> \"${battery_status}\" <<==' Script on Fallback mode,Unknown power supply status.Please copy this line and raise an issue to the Github Repo.Also run 'ls ${TMPDIR:-/tmp}/battery.notify' to see the list of lock files.*"
        touch "${TMPDIR:-/tmp}/battery.notify.status.fallback.$battery_status-$$"
      fi
      notify_thresholds
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

get_battery_info() {
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

handle_status_change() {
  get_battery_info

  if [ "$battery_status" != "$last_battery_status" ] || [ "$battery_percentage" != "$last_battery_percentage" ]; then
    last_battery_status=$battery_status
    last_battery_percentage=$battery_percentage
    print_verbose_state
    notify_thresholds

    if [[ "$battery_percentage" -le "$battery_low_threshold" ]]; then
      run_configured_command "${execute_low}"
    fi
    if [[ "$battery_percentage" -ge "$unplug_charger_threshold" ]]; then
      run_configured_command "${execute_unplug}"
    fi
    if ! $dock; then resolve_battery_status; fi
  fi
}

battery_full_threshold=${BATTERY_NOTIFY_THRESHOLD_FULL:-100}
battery_critical_threshold=${BATTERY_NOTIFY_THRESHOLD_CRITICAL:-5}
unplug_charger_threshold=${BATTERY_NOTIFY_THRESHOLD_UNPLUG:-80}
battery_low_threshold=${BATTERY_NOTIFY_THRESHOLD_LOW:-20}
timer=${BATTERY_NOTIFY_TIMER:-120}
notify=${BATTERY_NOTIFY_NOTIFY:-1140}
interval=${BATTERY_NOTIFY_INTERVAL:-5}
execute_critical=${BATTERY_NOTIFY_EXECUTE_CRITICAL:-"hyprshell session/suspend.sh"}
execute_low=${BATTERY_NOTIFY_EXECUTE_LOW:-}
execute_unplug=${BATTERY_NOTIFY_EXECUTE_UNPLUG:-}
execute_charging=${BATTERY_NOTIFY_EXECUTE_CHARGING:-}
execute_discharging=${BATTERY_NOTIFY_EXECUTE_DISCHARGING:-}

main() {
  trap 'find "${TMPDIR:-/tmp}" -maxdepth 1 -type f -name "battery.notify.status.fallback.*-$$" -delete 2>/dev/null || true' EXIT

  config_info
  if $verbose; then
    for line in "Verbose Mode is ON..." "" "" "" ""; do echo "${line}"; done
  fi
  get_battery_info
  last_notified_percentage=$battery_percentage
  prev_status=$battery_status
  last_full_notify_ts=0
  local battery_path=""
  battery_path="$(upower -e | grep battery || true)"
  [[ -n "${battery_path}" ]] || return 0
  dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',path='${battery_path}'" 2>/dev/null | while read -r battery_status_change; do handle_status_change; done
}

verbose=false
case "${1:-}" in
  -i | --info)
    config_info
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

check_range() {
  local value=$1 min=$2 max=$3 label=$4
  [[ $value =~ ^[0-9]+$ ]] && ((value >= min && value <= max)) ||
    printf '%s WARNING: %s must be %s - %s.\n' "$value" "$label" "$min" "$max" >&2
}

check_range "$battery_full_threshold" 50 100 "Full Threshold"
check_range "$battery_critical_threshold" 2 50 "Critical Threshold"
check_range "$battery_low_threshold" 10 80 "Low Threshold"
check_range "$unplug_charger_threshold" 40 100 "Unplug Threshold"
check_range "$timer" 60 1000 "Timer"
check_range "$notify" 1 1140 "Notify"
check_range "$interval" 1 10 "Interval"

main
