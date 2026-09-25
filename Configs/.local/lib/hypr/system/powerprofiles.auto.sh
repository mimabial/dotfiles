#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
workflows_script="${HYPR_LIB_DIR}/util/workflows.sh"

# Edge-triggered: the UPower root object also emits PropertiesChanged for
# LidIsClosed, and re-applying there would stomp a manually set profile.
apply_profile() {
  local battery=0 profile=balanced
  hypr_gamemode_active && return
  hypr_on_battery && { battery=1 profile=power-saver; }
  [[ "${battery}" == "${last_battery:--}" ]] && return
  last_battery="${battery}"
  [[ "$(hypr_power_profile)" == "${profile}" ]] || hypr_set_power_profile "${profile}"
}

sync_workflow() {
  local current previous saving=0
  hypr_gamemode_active && return
  [[ "$(hypr_power_profile)" == power-saver ]] && saving=1
  current="$(state_get HYPR_WORKFLOW default)"
  previous="$(state_get POWER_PROFILE_WORKFLOW_PREV "")"
  [[ "${current}" == gaming ]] && return
  if [[ "${saving}" == 1 ]]; then
    [[ -n "${previous}" ]] || state_set POWER_PROFILE_WORKFLOW_PREV "${current}" staterc
    [[ "${current}" == powersaver ]] || HYPR_WORKFLOW_UNLOCK=1 "${workflows_script}" --set powersaver >/dev/null
  elif [[ -n "${previous}" ]]; then
    [[ "${current}" != powersaver ]] || HYPR_WORKFLOW_UNLOCK=1 "${workflows_script}" --set "${previous}" >/dev/null
    state_set POWER_PROFILE_WORKFLOW_PREV "" staterc
  fi
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

changed="type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path="
exec {events}< <(dbus-monitor --system "${changed}'/org/freedesktop/UPower'" "${changed}'/org/freedesktop/UPower/PowerProfiles'" 2>/dev/null)
monitor=$!
trap 'kill "${monitor}" 2>/dev/null' EXIT
while read -r -u "${events}" line; do
  [[ "${line}" == *member=PropertiesChanged ]] || continue
  [[ "${line}" == *path=/org/freedesktop/UPower\;* ]] && apply_profile
  sync_workflow
done
exit 1
