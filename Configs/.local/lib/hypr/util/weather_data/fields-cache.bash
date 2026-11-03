weather_fields_cache_is_fresh() {
  local last_modified time_diff

  [ ! -f "$weather_fields_cache_path" ] && return 1
  last_modified=$(stat -c %Y "$weather_fields_cache_path" 2>/dev/null)
  time_diff=$((EPOCHSECONDS - last_modified))
  [ "$time_diff" -lt "$weather_fields_cache_max_age_seconds" ] && [ -s "$weather_fields_cache_path" ]
}

weather_fields_write_location_cache() {
  local -n weather_ref=$1
  if [ -n "${weather_ref[country]}" ] || [ -n "${weather_ref[city]}" ]; then
    cat >"$weather_location_cache_path" <<EOF
COUNTRY=${weather_ref[country]}
CITY=${weather_ref[city]}
EOF
  fi
}

weather_fields_write_weather_cache() {
  local -n weather_ref=$1
  cat >"$weather_fields_cache_path" <<EOF
WEATHER_ICON=${weather_ref[icon]}
WEATHER_DESC=${weather_ref[description]}
TEMP=${weather_ref[temperature]}
EOF
}

weather_fields_refresh_cache() {
  local -n weather_ref=$1
  weather_fields_resolve_location "$1" || return
  weather_fields_fetch_fields "$1"

  if [ -z "${weather_ref[condition_code]}" ] || [ -z "${weather_ref[description]}" ] || [ -z "${weather_ref[temperature]}" ]; then
    echo "Error: Failed to fetch weather data" >&2
    return 1
  fi

  [[ -d "$weather_fields_cache_dir" ]] || mkdir -p "$weather_fields_cache_dir"
  weather_fields_write_location_cache "$1"
  weather_fields_write_weather_cache "$1"
}

weather_fields_read_cached_value() {
  local var="$1"
  local value=""

  value=$(grep "^${var}=" "$weather_fields_cache_path" 2>/dev/null | cut -d'=' -f2-)
  if [ -z "$value" ]; then
    value=$(grep "^${var}=" "$weather_location_cache_path" 2>/dev/null | cut -d'=' -f2-)
  fi
  echo "$value"
}
