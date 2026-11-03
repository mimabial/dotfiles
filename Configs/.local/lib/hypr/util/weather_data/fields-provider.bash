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
  local location_query="$1"
  curl -fsS --max-time "${WEATHER_REQUEST_TIMEOUT_SECONDS}" "https://wttr.in/${location_query}?format=j1" 2>/dev/null
}

weather_fields_format_temperature() {
  local -n weather_ref=$1
  local celsius="${weather_ref[temperature]}"
  if [ -n "$celsius" ]; then
    if [[ "$celsius" == -* || "$celsius" == +* ]]; then
      weather_ref[temperature]="${celsius}°C"
    else
      weather_ref[temperature]="+${celsius}°C"
    fi
  fi
}

weather_fields_decode_json() {
  local -n weather_ref=$1
  local weather_json="$2"
  local condition_code="" description="" temperature="" parsed_city="" parsed_country=""
  local IFS=$'\t'

  read -r condition_code description temperature parsed_city parsed_country < <(
    jq -r '[
      (.current_condition[0].weatherCode // ""),
      (.current_condition[0].weatherDesc[0].value // ""),
      (.current_condition[0].FeelsLikeC // ""),
      (.nearest_area[0].areaName[0].value // ""),
      (.nearest_area[0].country[0].value // "")
    ] | @tsv' <<<"$weather_json" 2>/dev/null
  )
  weather_ref[condition_code]="$condition_code"
  weather_ref[description]="$description"
  weather_ref[temperature]="$temperature"
  if [ -z "${weather_ref[city]}" ] || [ "${weather_ref[city]}" = "${weather_ref[location_query]}" ]; then
    weather_ref[city]="${parsed_city}"
  fi
  if [ -z "${weather_ref[country]}" ]; then
    weather_ref[country]="${parsed_country}"
  fi
  weather_fields_format_temperature "$1"
}

weather_fields_fetch_fields() {
  local -n weather_ref=$1
  local weather_json=""

  weather_json="$(weather_fields_fetch_json "${weather_ref[location_query]}")"
  [ -z "$weather_json" ] || weather_fields_decode_json "$1" "$weather_json"
  weather_ref[icon]=$(weather_fields_icon_for_code "${weather_ref[condition_code]}")
}
