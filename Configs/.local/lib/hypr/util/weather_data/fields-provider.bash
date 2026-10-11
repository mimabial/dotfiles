weather_fields_icon_for_code() {
  local weather_condition_code="$1"
  local json_file="${BASH_SOURCE[0]%/*}/../weather_codes.json"

  if [ -f "$json_file" ] && command -v jq >/dev/null 2>&1; then
    jq -r ".[\"$weather_condition_code\"] // .default" "$json_file" 2>/dev/null
  else
    echo "󰖐"
  fi
}

weather_fields_fetch_json() {
  curl -fsS --max-time "${WEATHER_REQUEST_TIMEOUT_SECONDS}" "https://wttr.in/${weather_location_query}?format=j1" 2>/dev/null
}

weather_fields_format_temperature() {
  if [ -n "$weather_temperature_celsius" ]; then
    if [[ "$weather_temperature_celsius" == -* || "$weather_temperature_celsius" == +* ]]; then
      weather_temperature_celsius="${weather_temperature_celsius}°C"
    else
      weather_temperature_celsius="+${weather_temperature_celsius}°C"
    fi
  fi
}

weather_fields_decode_json() {
  local weather_json="$1"
  local parsed_city="" parsed_country=""
  local IFS=$'\t'

  read -r weather_condition_code weather_description weather_temperature_celsius parsed_city parsed_country < <(
    jq -r '[
      (.current_condition[0].weatherCode // ""),
      (.current_condition[0].weatherDesc[0].value // ""),
      (.current_condition[0].FeelsLikeC // ""),
      (.nearest_area[0].areaName[0].value // ""),
      (.nearest_area[0].country[0].value // "")
    ] | @tsv' <<<"$weather_json" 2>/dev/null
  )
  if [ -z "$weather_city" ] || [ "$weather_city" = "$weather_location_query" ]; then
    weather_city="${parsed_city}"
  fi
  if [ -z "$weather_country" ]; then
    weather_country="${parsed_country}"
  fi
  weather_fields_format_temperature
}

weather_fields_fetch_fields() {
  local weather_json=""

  weather_json="$(weather_fields_fetch_json)"
  [ -z "$weather_json" ] || weather_fields_decode_json "$weather_json"
  weather_condition_icon=$(weather_fields_icon_for_code "$weather_condition_code")
}
