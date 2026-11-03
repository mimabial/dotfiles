#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell bluetooth/power {on|off|toggle|is-on}" "$@"

bluetooth_is_powered() {
  [[ "$(hypr_daemon_call bluetoothctl show 2>/dev/null)" == *'Powered: yes'* ]]
}

BLUETOOTH_POWER_SWITCH_TIMEOUT_S=5

set_power() {
  local enabled="$1"
  if [[ "$(hypr_daemon_call gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner org.blueman.Applet 2>/dev/null)" == '(true,)' ]]; then
    hypr_daemon_call gdbus call --session --dest org.blueman.Applet --object-path /org/blueman/Applet --method org.blueman.Applet.SetBluetoothStatus "${enabled}" >/dev/null
  elif [[ "${enabled}" == true ]]; then
    if rfkill list bluetooth >/dev/null 2>&1; then
      rfkill unblock bluetooth
    fi
    bluetooth_is_powered || timeout "${BLUETOOTH_POWER_SWITCH_TIMEOUT_S}s" bluetoothctl power on >/dev/null
  elif rfkill list bluetooth >/dev/null 2>&1; then
    rfkill block bluetooth
  else
    timeout "${BLUETOOTH_POWER_SWITCH_TIMEOUT_S}s" bluetoothctl power off >/dev/null
  fi
}

case "${1:-}" in
  on) set_power true ;;
  off) set_power false ;;
  toggle)
    if bluetooth_is_powered; then set_power false; else set_power true; fi
    ;;
  is-on) bluetooth_is_powered ;;
  *)
    printf 'Usage: hyprshell bluetooth/power {on|off|toggle|is-on}\n' >&2
    exit 1
    ;;
esac
