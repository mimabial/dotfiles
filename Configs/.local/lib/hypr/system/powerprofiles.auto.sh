#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
workflows_script="${HYPR_LIB_DIR}/util/workflows.sh"

gamemode_active() {
  [[ "$(busctl --user get-property com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount 2>/dev/null)" =~ ^i[[:space:]]+[1-9][0-9]*$ ]]
}

on_battery() {
  [[ "$(busctl --system get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null)" == 'b true' ]]
}

active_profile() {
  local _ profile
  read -r _ profile < <(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile)
  printf '%s\n' "${profile//\"/}"
}

apply_profile() {
  local profile=balanced
  gamemode_active && return
  on_battery && profile=power-saver
  [[ "$(active_profile)" == "${profile}" ]] || busctl --system set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile s "${profile}"
}

sync_workflow() {
  local profile current previous target=""
  gamemode_active && return
  profile="$(active_profile)"
  current="$(state_get HYPR_WORKFLOW default)"
  previous="$(state_get POWER_PROFILE_WORKFLOW_PREV "")"
  [[ "${profile}" == power-saver ]] && target=powersaver
  [[ "${profile}" == performance ]] && target=snappy
  if [[ -n "${target}" && "${current}" != gaming ]]; then
    [[ -n "${previous}" ]] || state_set POWER_PROFILE_WORKFLOW_PREV "${current}" staterc
    [[ "${current}" == "${target}" ]] || HYPR_WORKFLOW_UNLOCK=1 "${workflows_script}" --set "${target}" >/dev/null
  elif [[ -z "${target}" && -n "${previous}" && "${current}" != gaming ]]; then
    [[ "${current}" != powersaver && "${current}" != snappy ]] || HYPR_WORKFLOW_UNLOCK=1 "${workflows_script}" --set "${previous}" >/dev/null
    state_set POWER_PROFILE_WORKFLOW_PREV "" staterc
  fi
}

watch_events() {
  busctl --system wait org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.DBus.Properties PropertiesChanged >/dev/null & battery_pid=$!
  busctl --system wait org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties PropertiesChanged >/dev/null & profile_pid=$!
}

case "${1:-}" in
  "") once=0 ;;
  --once) once=1 ;;
  -h|--help) printf 'Usage: %s [--once]\n' "${0##*/}"; exit ;;
  *) exit 2 ;;
esac

apply_profile
sync_workflow
((once)) && exit

watch_events
while true; do
  battery_event_pid="${battery_pid}"
  wait -n -p source_pid "${battery_pid}" "${profile_pid}" || exit 1
  kill "${battery_pid}" "${profile_pid}" 2>/dev/null || true
  wait "${battery_pid}" "${profile_pid}" 2>/dev/null || true
  watch_events
  [[ "${source_pid}" == "${battery_event_pid}" ]] && apply_profile
  sync_workflow
done
