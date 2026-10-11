#!/usr/bin/env bash

hypr_dbus_get() {
  local bus="$1" destination="$2" object_path="$3" interface="$4" property="$5" reply=""

  reply="$(dbus-send "--${bus}" --print-reply=literal --dest="${destination}" "${object_path}" org.freedesktop.DBus.Properties.Get "string:${interface}" "string:${property}" 2>/dev/null)" || return
  printf '%s\n' "${reply##* }"
}

hypr_dbus_set() {
  local bus="$1" destination="$2" object_path="$3" interface="$4" property="$5" value_type="$6" value="$7"

  dbus-send "--${bus}" --print-reply=literal --reply-timeout=5000 --dest="${destination}" "${object_path}" org.freedesktop.DBus.Properties.Set "string:${interface}" "string:${property}" "variant:${value_type}:${value}" >/dev/null
}

hypr_login1_call() {
  local method="$1"
  shift
  dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 "org.freedesktop.login1.Manager.${method}" "$@"
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
