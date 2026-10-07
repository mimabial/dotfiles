#!/usr/bin/env bash

hypr_dbus_get() {
  local reply=""

  reply="$(dbus-send "--$1" --print-reply=literal --dest="$2" "$3" org.freedesktop.DBus.Properties.Get "string:$4" "string:$5" 2>/dev/null)" || return
  printf '%s\n' "${reply##* }"
}

hypr_dbus_set() {
  dbus-send "--$1" --print-reply=literal --reply-timeout=5000 --dest="$2" "$3" org.freedesktop.DBus.Properties.Set "string:$4" "string:$5" "variant:$6:$7" >/dev/null
}

hypr_gamemode_active() {
  local clients=""

  clients="$(hypr_dbus_get session com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount)" && ((clients > 0))
}

hypr_on_battery() {
  [[ "$(hypr_dbus_get system org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery)" == true ]]
}

hypr_power_profile() {
  hypr_dbus_get system org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile
}

hypr_set_power_profile() {
  hypr_dbus_set system org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile string "$1"
}
