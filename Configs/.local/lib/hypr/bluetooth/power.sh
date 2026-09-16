#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell bluetooth/power {on|off|toggle|is-on}" "$@"

powered() {
  timeout 2s bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'
}

power_on() {
  if rfkill list bluetooth >/dev/null 2>&1; then
    rfkill unblock bluetooth
  fi
  powered || timeout 5s bluetoothctl power on >/dev/null
}

power_off() {
  if rfkill list bluetooth >/dev/null 2>&1; then
    rfkill block bluetooth
  else
    timeout 5s bluetoothctl power off >/dev/null
  fi
}

case "${1:-}" in
  on) power_on ;;
  off) power_off ;;
  toggle)
    if powered; then power_off; else power_on; fi
    ;;
  is-on) powered ;;
  *)
    printf 'Usage: hyprshell bluetooth/power {on|off|toggle|is-on}\n' >&2
    exit 1
    ;;
esac
