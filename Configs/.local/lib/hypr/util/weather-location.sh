#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_runtime_require state || exit 1

hypr_help_guard "Usage: hyprshell util/weather-location [CITY|--clear|--pin LAT,LON LABEL]
Set the location weather reports for, then refetch.
  --clear            forget the override, back to automatic detection
  --pin COORDS NAME  pin exact coordinates and the name to show for them" "$@"

case "${1:-}" in
  "")
    printf '%s\n' "${WEATHER_LOCATION:-$(state_get WEATHER_LOCATION)}"
    exit 0
    ;;
  --clear | clear)
    state_set "WEATHER_LOCATION" "" "staterc"
    state_set "WEATHER_LOCATION_LABEL" "" "staterc"
    ;;
  --pin)
    [[ -n "${2:-}" ]] || { echo "weather-location: --pin needs COORDS" >&2; exit 2; }
    state_set "WEATHER_LOCATION" "$2" "staterc"
    state_set "WEATHER_LOCATION_LABEL" "${3:-}" "staterc"
    ;;
  *)
    state_set "WEATHER_LOCATION" "$1" "staterc"
    state_set "WEATHER_LOCATION_LABEL" "" "staterc"
    ;;
esac

rm -f "${HOME}/.cache/wttr/weather_data.json"
WEATHER_LOCATION="$(state_get WEATHER_LOCATION)" hyprshell weather --force >/dev/null 2>&1 || true
