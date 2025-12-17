#!/bin/bash

CACHE_DIR="$HOME/.cache/wttr"
WEATHER_CACHE="$CACHE_DIR/weather.cache"
LOCATION_CACHE="$CACHE_DIR/location.cache"
EXPIRY_TIME=3600

# Get Nerd Font icon for weather code
get_nerd_icon() {
  local code="$1"
  local json_file="$(dirname "$(readlink -f "$0")")/weather_codes.json"

  if [ -f "$json_file" ] && command -v jq >/dev/null 2>&1; then
    local icon=$(jq -r ".[\"$code\"] // .default" "$json_file" 2>/dev/null)
    echo "$icon"
  else
    # Fallback if JSON file or jq not available
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
  [ ! -f "$WEATHER_CACHE" ] && return 1

  local last_modified=$(stat -c %Y "$WEATHER_CACHE" 2>/dev/null)
  local current_date=$(date +%s)
  local time_diff=$((current_date - last_modified))

  [ $time_diff -lt $EXPIRY_TIME ] && [ -s "$WEATHER_CACHE" ]
}

refresh_cache() {
  local country=""
  local city=""

  # Priority 1: Check WEATHER_LOCATION environment variable
  if [ -n "$WEATHER_LOCATION" ]; then
    city="$WEATHER_LOCATION"
  else
    # Priority 2: Fetch location from IP
    local location=$(curl -s --max-time 5 ipinfo.io 2>/dev/null)
    country=$(echo "$location" | jq -r '.country' 2>/dev/null)
    city=$(echo "$location" | jq -r '.city' 2>/dev/null)

    # Validate data
    [ "$country" = "null" ] && country=""
    [ "$city" = "null" ] && city=""

    # Priority 3: If location fetch failed, try to read from location cache
    if [ -z "$country" ] && [ -z "$city" ] && [ -f "$LOCATION_CACHE" ]; then
      country=$(grep "^COUNTRY=" "$LOCATION_CACHE" 2>/dev/null | cut -d'=' -f2-)
      city=$(grep "^CITY=" "$LOCATION_CACHE" 2>/dev/null | cut -d'=' -f2-)
    fi
  fi

  # Build location parameter for wttr.in
  local location=""
  if [ -n "$city" ]; then
    location="$city"
  else
    # Final fallback to Paris if all else fails
    location="Paris"
  fi

  # Fetch weather using JSON format to get numeric weather code
  local weather_json=$(curl -s --max-time 5 "wttr.in/${location}?format=j1" 2>/dev/null)

  # Extract weather data using jq
  if command -v jq >/dev/null 2>&1 && [ -n "$weather_json" ]; then
    code=$(echo "$weather_json" | jq -r '.current_condition[0].weatherCode' 2>/dev/null)
    desc=$(echo "$weather_json" | jq -r '.current_condition[0].weatherDesc[0].value' 2>/dev/null)
    temp=$(echo "$weather_json" | jq -r '.current_condition[0].FeelsLikeC' 2>/dev/null)
    temp="+${temp}°C"
  else
    # Fallback to simple format if jq is not available
    local weather=$(curl -s --max-time 5 "wttr.in/${location}?format=%c|%C|%f" 2>/dev/null)
    IFS='|' read -r code desc temp <<<"$weather"
  fi

  # Convert weather code to Nerd Font icon
  local icon=$(get_nerd_icon "$code")

  if [ -z "$code" ] || [ -z "$desc" ] || [ -z "$temp" ]; then
    echo "Error: Failed to fetch weather data" >&2
    return 1
  fi

  # Write to caches
  mkdir -p "$CACHE_DIR"

  # Write location cache (only if we have location data)
  if [ -n "$country" ] || [ -n "$city" ]; then
    cat >"$LOCATION_CACHE" <<EOF
COUNTRY=$country
CITY=$city
EOF
  fi

  # Write weather cache
  cat >"$WEATHER_CACHE" <<EOF
WEATHER_ICON=$icon
WEATHER_DESC=$desc
TEMP=$temp
EOF
}

get_var() {
  local var="$1"
  # Try weather cache first, then location cache
  local value=$(grep "^${var}=" "$WEATHER_CACHE" 2>/dev/null | cut -d'=' -f2-)
  if [ -z "$value" ]; then
    value=$(grep "^${var}=" "$LOCATION_CACHE" 2>/dev/null | cut -d'=' -f2-)
  fi
  echo "$value"
}

# Parse arguments
FORCE=false
VARS=()

for arg in "$@"; do
  case $arg in
    -f) FORCE=true ;;
    -h | --help)
      show_usage
      exit 0
      ;;
    -c) VARS+=("CITY") ;;
    -l) VARS+=("COUNTRY") ;;
    -i) VARS+=("WEATHER_ICON") ;;
    -d) VARS+=("WEATHER_DESC") ;;
    -t) VARS+=("TEMP") ;;
    --*)
      VAR="${arg#--}"
      VAR="${VAR//-/_}"
      VAR="${VAR^^}"
      VARS+=("$VAR")
      ;;
    *) VARS+=("$arg") ;;
  esac
done

# Refresh if needed
if [ "$FORCE" = true ] || ! is_cache_valid; then
  refresh_cache || exit 1
fi

# Output
if [ ${#VARS[@]} -eq 0 ]; then
  # Show all data from both caches
  [ -f "$LOCATION_CACHE" ] && cat "$LOCATION_CACHE"
  [ -f "$WEATHER_CACHE" ] && cat "$WEATHER_CACHE"
else
  output=()
  for var in "${VARS[@]}"; do
    output+=("$(get_var "$var")")
  done
  echo "${output[*]}"
fi
