weather_fields_cache_is_fresh() {
  local last_modified time_diff

  [ ! -f "$weather_fields_cache_path" ] && return 1
  last_modified=$(stat -c %Y "$weather_fields_cache_path" 2>/dev/null)
  time_diff=$((EPOCHSECONDS - last_modified))
  [ "$time_diff" -lt "$weather_fields_cache_max_age_seconds" ] && [ -s "$weather_fields_cache_path" ]
}

weather_fields_write_location_cache() {
  if [ -n "$weather_country" ] || [ -n "$weather_city" ]; then
    cat >"$weather_location_cache_path" <<EOF
COUNTRY=$weather_country
CITY=$weather_city
EOF
  fi
}

weather_fields_write_weather_cache() {
  cat >"$weather_fields_cache_path" <<EOF
WEATHER_ICON=$weather_condition_icon
WEATHER_DESC=$weather_description
TEMP=$weather_temperature_celsius
EOF
}

weather_fields_refresh_cache() {
  weather_fields_resolve_location || return
  weather_fields_fetch_fields

  if [ -z "$weather_condition_code" ] || [ -z "$weather_description" ] || [ -z "$weather_temperature_celsius" ]; then
    echo "Error: Failed to fetch weather data" >&2
    return 1
  fi

  mkdir -p "$weather_fields_cache_dir"
  weather_fields_write_location_cache
  weather_fields_write_weather_cache
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
