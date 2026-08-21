#!/usr/bin/env bash
# Persist the weather location and refetch. weather.py reads WEATHER_LOCATION
# from staterc, so the choice survives a restart; clearing it falls back to the
# theme coordinates or the cached city as before.
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

# the cache is keyed to the old place, so drop it before refetching
rm -f "${HOME}/.cache/wttr/weather_data.json"
WEATHER_LOCATION="$(state_get WEATHER_LOCATION)" hyprshell weather --force >/dev/null 2>&1 || true
