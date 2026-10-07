#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell bluetooth/power {on|off|toggle|is-on}" "$@"

bluetooth_is_powered() {
  hypr_daemon_call bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'
}

BLUETOOTH_POWER_SWITCH_TIMEOUT_S=5

power_on() {
  if rfkill list bluetooth >/dev/null 2>&1; then
    rfkill unblock bluetooth
  fi
  bluetooth_is_powered || timeout "${BLUETOOTH_POWER_SWITCH_TIMEOUT_S}s" bluetoothctl power on >/dev/null
}

power_off() {
  if rfkill list bluetooth >/dev/null 2>&1; then
    rfkill block bluetooth
  else
    timeout "${BLUETOOTH_POWER_SWITCH_TIMEOUT_S}s" bluetoothctl power off >/dev/null
  fi
}

case "${1:-}" in
  on) power_on ;;
  off) power_off ;;
  toggle)
    if bluetooth_is_powered; then power_off; else power_on; fi
    ;;
  is-on) bluetooth_is_powered ;;
  *)
    printf 'Usage: hyprshell bluetooth/power {on|off|toggle|is-on}\n' >&2
    exit 1
    ;;
esac
