#!/bin/bash

CACHE_DIR="$HOME/.cache/wttr"
WEATHER_CACHE="$CACHE_DIR/weather.cache"
LOCATION_CACHE="$CACHE_DIR/location.cache"
EXPIRY_TIME=3600
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATERC_FILE="${STATE_HOME}/hypr/staterc"
ENV_OVERRIDES_FILE="${STATE_HOME}/hypr/env-overrides"
FORCE=false
VARS=()
country=""
city=""
location=""
code=""
desc=""
temp=""
icon=""

load_env_file() {
  local filepath="$1"
  [[ -r "${filepath}" ]] || return 0

  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "${line}" == \#* ]] && continue
    [[ "${line}" == export\ * ]] && line="${line#export }"
    [[ "${line}" == *=* ]] || continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    export "${key}=${value}"
  done <"${filepath}"
}

env_flag() {
  local value="${1:-}"
  case "${value,,}" in
    true|1|t|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_theme_coordinates() {
  local latitude="${AUTO_THEME_LATITUDE:-}"
  local longitude="${AUTO_THEME_LONGITUDE:-}"

  [[ -n "${latitude}" && -n "${longitude}" ]] || return 1
  [[ "${latitude,,}" != "auto" && "${longitude,,}" != "auto" ]] || return 1
  printf '%s,%s\n' "${latitude}" "${longitude}"
}

get_nerd_icon() {
  local code="$1"
  local json_file="$(dirname "$(readlink -f "$0")")/weather_codes.json"

  if [ -f "$json_file" ] && command -v jq >/dev/null 2>&1; then
    jq -r ".[\"$code\"] // .default" "$json_file" 2>/dev/null
  else
    echo "󰖐"
  fi
}

show_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [VARIABLES]

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
    $(basename "$0")               # Show all data
    $(basename "$0") --city        # Get city only
    $(basename "$0") -i -d -t      # Icon, desc, temp on one line
    $(basename "$0") -t -f         # Temp with force refresh
EOF
}

is_cache_valid() {
  local last_modified current_date time_diff

  [ ! -f "$WEATHER_CACHE" ] && return 1
  last_modified=$(stat -c %Y "$WEATHER_CACHE" 2>/dev/null)
  current_date=$(date +%s)
  time_diff=$((current_date - last_modified))
  [ "$time_diff" -lt "$EXPIRY_TIME" ] && [ -s "$WEATHER_CACHE" ]
}

read_location_cache() {
  [[ -f "$LOCATION_CACHE" ]] || return 0
  country=$(grep "^COUNTRY=" "$LOCATION_CACHE" 2>/dev/null | cut -d'=' -f2-)
  city=$(grep "^CITY=" "$LOCATION_CACHE" 2>/dev/null | cut -d'=' -f2-)
}

resolve_weather_location() {
  if [ -n "${WEATHER_LOCATION:-}" ]; then
    city="$WEATHER_LOCATION"
    location="$city"
    return 0
  fi

  location="$(resolve_theme_coordinates 2>/dev/null || true)"
  if [ -z "$location" ]; then
    read_location_cache
    [ -n "$city" ] && location="$city"
  fi

  if [ -z "$location" ] && env_flag "${WEATHER_ALLOW_AUTO_GEOLOCATION:-false}"; then
    load_geolocated_location
  fi

  if [ -n "$location" ]; then
    return 0
  fi
  if [ -n "$city" ]; then
    location="$city"
  else
    location="Paris"
  fi
}

load_geolocated_location() {
  local ipinfo_json=""

  ipinfo_json=$(curl -fsS --max-time 5 "https://ipinfo.io/json" 2>/dev/null)
  country=$(echo "$ipinfo_json" | jq -r '.country' 2>/dev/null)
  city=$(echo "$ipinfo_json" | jq -r '.city' 2>/dev/null)
  location=$(echo "$ipinfo_json" | jq -r '.loc // .city // empty' 2>/dev/null)

  [ "$country" = "null" ] && country=""
  [ "$city" = "null" ] && city=""
  [ "$location" = "null" ] && location=""
}

fetch_weather_json() {
  curl -fsS --max-time 5 "https://wttr.in/${location}?format=j1" 2>/dev/null
}

format_temperature() {
  if [ -n "$temp" ]; then
    if [[ "$temp" == -* || "$temp" == +* ]]; then
      temp="${temp}°C"
    else
      temp="+${temp}°C"
    fi
  fi
}

parse_json_weather() {
  local weather_json="$1"

  code=$(echo "$weather_json" | jq -r '.current_condition[0].weatherCode // empty' 2>/dev/null)
  desc=$(echo "$weather_json" | jq -r '.current_condition[0].weatherDesc[0].value // empty' 2>/dev/null)
  temp=$(echo "$weather_json" | jq -r '.current_condition[0].FeelsLikeC // empty' 2>/dev/null)
  if [ -z "$city" ] || [ "$city" = "$location" ]; then
    city=$(echo "$weather_json" | jq -r '.nearest_area[0].areaName[0].value // empty' 2>/dev/null)
  fi
  if [ -z "$country" ]; then
    country=$(echo "$weather_json" | jq -r '.nearest_area[0].country[0].value // empty' 2>/dev/null)
  fi
  format_temperature
}

parse_simple_weather() {
  local weather=""
  weather=$(curl -fsS --max-time 5 "https://wttr.in/${location}?format=%c|%C|%f" 2>/dev/null)
  IFS='|' read -r code desc temp <<<"$weather"
}

fetch_weather_data() {
  local weather_json=""

  weather_json="$(fetch_weather_json)"
  if command -v jq >/dev/null 2>&1 && [ -n "$weather_json" ]; then
    parse_json_weather "$weather_json"
  else
    parse_simple_weather
  fi
  icon=$(get_nerd_icon "$code")
}

write_location_cache() {
  if [ -n "$country" ] || [ -n "$city" ]; then
    cat >"$LOCATION_CACHE" <<EOF
COUNTRY=$country
CITY=$city
EOF
  fi
}

write_weather_cache() {
  cat >"$WEATHER_CACHE" <<EOF
WEATHER_ICON=$icon
WEATHER_DESC=$desc
TEMP=$temp
EOF
}

refresh_cache() {
  resolve_weather_location
  fetch_weather_data

  if [ -z "$code" ] || [ -z "$desc" ] || [ -z "$temp" ]; then
    echo "Error: Failed to fetch weather data" >&2
    return 1
  fi

  mkdir -p "$CACHE_DIR"
  write_location_cache
  write_weather_cache
}

get_var() {
  local var="$1"
  local value=""

  value=$(grep "^${var}=" "$WEATHER_CACHE" 2>/dev/null | cut -d'=' -f2-)
  if [ -z "$value" ]; then
    value=$(grep "^${var}=" "$LOCATION_CACHE" 2>/dev/null | cut -d'=' -f2-)
  fi
  echo "$value"
}

parse_args() {
  local arg="" var=""

  for arg in "$@"; do
    case "$arg" in
      -f) FORCE=true ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      -c) VARS+=("CITY") ;;
      -l) VARS+=("COUNTRY") ;;
      -i) VARS+=("WEATHER_ICON") ;;
      -d) VARS+=("WEATHER_DESC") ;;
      -t) VARS+=("TEMP") ;;
      --*)
        var="${arg#--}"
        var="${var//-/_}"
        var="${var^^}"
        VARS+=("$var")
        ;;
      *) VARS+=("$arg") ;;
    esac
  done
}

print_output() {
  local output=()
  local var=""

  if [ ${#VARS[@]} -eq 0 ]; then
    [ -f "$LOCATION_CACHE" ] && cat "$LOCATION_CACHE"
    [ -f "$WEATHER_CACHE" ] && cat "$WEATHER_CACHE"
    return 0
  fi

  for var in "${VARS[@]}"; do
    output+=("$(get_var "$var")")
  done
  echo "${output[*]}"
}

main() {
  load_env_file "${STATERC_FILE}"
  load_env_file "${ENV_OVERRIDES_FILE}"
  parse_args "$@"

  if [ "$FORCE" = true ] || ! is_cache_valid; then
    refresh_cache || exit 1
  fi

  print_output
}

main "$@"
