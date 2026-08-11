#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

gamemode_active() {
  [[ "$(busctl --user get-property com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount 2>/dev/null)" =~ ^i[[:space:]]+[1-9][0-9]*$ ]]
}

on_battery() {
  [[ "$(busctl --system get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null)" == 'b true' ]]
}

apply_profile() {
  local profile=balanced
  gamemode_active && return
  on_battery && profile=power-saver
  busctl --system set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile s "${profile}"
}

case "${1:-}" in
  "") once=0 ;;
  --once) once=1 ;;
  -h|--help) printf 'Usage: %s [--once]\n' "${0##*/}"; exit ;;
  *) exit 2 ;;
esac

apply_profile
((once)) && exit

while busctl --system wait org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.DBus.Properties PropertiesChanged >/dev/null; do
  apply_profile
done
exit 1
