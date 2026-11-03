#!/usr/bin/env bash

set -euo pipefail

weather_fields_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wttr"
weather_fields_cache_path="$weather_fields_cache_dir/weather.cache"
weather_location_cache_path="$weather_fields_cache_dir/location.cache"
weather_fields_cache_max_age_seconds=3600
weather_fields_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
weather_fields_state_path="${weather_fields_state_home}/hypr/staterc"
weather_fields_overrides_path="${weather_fields_state_home}/hypr/env-overrides"

weather_fields_show_usage() {
  cat <<EOF
Usage: hyprshell util/weather-fields [OPTIONS] [VARIABLES]

Retrieve cached weather/location data or refresh cache.

VARIABLES:
    --city, -c          City name
    --country, -l       Country code
    --weather-icon, -i  Weather icon
    --weather-desc, -d  Weather description
    --temp, -t          Temperature
    (no arg shows all, multiple args output space-separated)

OPTIONS:
    -f    Force refresh cache
    -h    Show this help

EXAMPLES:
    hyprshell util/weather-fields               # Show all data
    hyprshell util/weather-fields --city        # Get city only
    hyprshell util/weather-fields -i -d -t      # Icon, desc, temp on one line
    hyprshell util/weather-fields -t -f         # Temp with force refresh
EOF
}

weather_fields_parse_args_into() {
  local -n requested_fields_ref=$1 force_refresh_ref=$2
  local arg="" var=""
  shift 2

  for arg in "$@"; do
    case "$arg" in
      -f) force_refresh_ref=true ;;
      -h|--help)
        weather_fields_show_usage
        exit 0
        ;;
      -c) requested_fields_ref+=("CITY") ;;
      -l) requested_fields_ref+=("COUNTRY") ;;
      -i) requested_fields_ref+=("WEATHER_ICON") ;;
      -d) requested_fields_ref+=("WEATHER_DESC") ;;
      -t) requested_fields_ref+=("TEMP") ;;
      --*)
        var="${arg#--}"
        var="${var//-/_}"
        var="${var^^}"
        requested_fields_ref+=("$var")
        ;;
      *) requested_fields_ref+=("$arg") ;;
    esac
  done
}

weather_fields_print_output() {
  local output=()
  local var=""

  if [ $# -eq 0 ]; then
    [ -f "$weather_location_cache_path" ] && cat "$weather_location_cache_path"
    [ -f "$weather_fields_cache_path" ] && cat "$weather_fields_cache_path"
    return 0
  fi

  for var in "$@"; do
    output+=("$(weather_fields_read_cached_value "$var")")
  done
  echo "${output[*]}"
}

main() {
  local -a requested_fields=()
  local force_refresh=false
  local -A weather=(
    [country]="" [city]="" [location_query]="" [condition_code]="" [description]="" [temperature]="" [icon]=""
  )
  weather_fields_load_env_file "${weather_fields_state_path}"
  weather_fields_load_env_file "${weather_fields_overrides_path}"
  weather_fields_parse_args_into requested_fields force_refresh "$@"

  if [ "$force_refresh" = true ] || ! weather_fields_cache_is_fresh; then
    weather_fields_refresh_cache weather || exit 1
  fi

  weather_fields_print_output "${requested_fields[@]}"
}

WEATHER_REQUEST_TIMEOUT_SECONDS=5
source "${BASH_SOURCE[0]%/*}/weather_data/fields-location.bash"
source "${BASH_SOURCE[0]%/*}/weather_data/fields-provider.bash"
source "${BASH_SOURCE[0]%/*}/weather_data/fields-cache.bash"

main "$@"
