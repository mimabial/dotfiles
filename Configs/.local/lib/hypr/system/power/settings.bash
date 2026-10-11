power_config_path="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/power-manager.json"
POWER_DEFAULT_BATTERY_THRESHOLD_PERCENT=20

power_manager_enabled() {
  [[ -f "$power_config_path" ]] && jq -e '.enabled == true' "$power_config_path" >/dev/null 2>&1
}

power_setting() {
  local key="$1" fallback="$2" value=""
  value="$(jq -r --arg key "$key" 'getpath($key | split(".")) // empty' "$power_config_path" 2>/dev/null)" || true
  printf '%s\n' "${value:-$fallback}"
}

power_source_state() {
  local percentage="" threshold=""
  if ! hypr_on_battery; then
    printf 'ac\n'
    return
  fi
  percentage="$(hypr_dbus_get system org.freedesktop.UPower /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device Percentage 2>/dev/null || true)"
  threshold="$(power_setting batteryThreshold "${POWER_DEFAULT_BATTERY_THRESHOLD_PERCENT}")"
  if [[ "$percentage" =~ ^[0-9]+([.][0-9]+)?$ && "$threshold" =~ ^[0-9]+$ ]]; then
    if awk -v percent="$percentage" -v limit="$threshold" 'BEGIN { exit !(percent > 0 && percent <= limit) }'; then
      printf 'batteryLow\n'
      return
    fi
  fi
  printf 'batteryHigh\n'
}

power_valid_profile() {
  [[ "$1" == balanced || "$1" == power-saver || "$1" == performance ]]
}

power_valid_action() {
  case "$1" in
    ignore|suspend|hibernate|suspend-then-hibernate|hybrid-sleep|poweroff) return 0 ;;
    *) return 1 ;;
  esac
}
