weather_fields_load_env_file() {
  local filepath="$1"
  [[ -r "${filepath}" ]] || return 0

  # shellcheck source=/dev/null
  source "${filepath}"
}

weather_fields_env_flag() {
  local value="${1:-}"
  case "${value,,}" in
    true|1|t|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

weather_fields_resolve_theme_coordinates() {
  local latitude="${AUTO_THEME_LATITUDE:-}"
  local longitude="${AUTO_THEME_LONGITUDE:-}"

  [[ -n "${latitude}" || -n "${longitude}" ]] || return 1
  if [[ -z "${latitude}" || -z "${longitude}" ]]; then
    printf 'Error: AUTO_THEME_LATITUDE and AUTO_THEME_LONGITUDE must both be set\n' >&2
    return 2
  fi
  if [[ "${latitude,,}" == "auto" || "${longitude,,}" == "auto" ]]; then
    if [[ "${latitude,,}" == "auto" && "${longitude,,}" == "auto" ]]; then
      return 1
    fi
    printf 'Error: AUTO_THEME_LATITUDE and AUTO_THEME_LONGITUDE must both be explicit coordinates\n' >&2
    return 2
  fi
  if [[ ! "${latitude}" =~ ^-?[0-9]+([.][0-9]+)?$ || ! "${longitude}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf 'Error: invalid theme coordinates: %s,%s\n' "${latitude}" "${longitude}" >&2
    return 2
  fi
  printf '%s,%s\n' "${latitude}" "${longitude}"
}

weather_fields_update_location_from_cache() {
  [[ -f "$weather_location_cache_path" ]] || return 0
  weather_country=$(grep "^COUNTRY=" "$weather_location_cache_path" 2>/dev/null | cut -d'=' -f2-)
  weather_city=$(grep "^CITY=" "$weather_location_cache_path" 2>/dev/null | cut -d'=' -f2-)
}

weather_fields_resolve_location() {
  local rc=0

  if [ -n "${WEATHER_LOCATION:-}" ]; then
    weather_city="$WEATHER_LOCATION"
    weather_location_query="$weather_city"
    return 0
  fi

  if weather_location_query="$(weather_fields_resolve_theme_coordinates)"; then
    return 0
  else
    rc=$?
  fi
  if [ "${rc}" -gt 1 ]; then
    return "${rc}"
  fi

  if [ -z "$weather_location_query" ]; then
    weather_fields_update_location_from_cache
    [ -n "$weather_city" ] && weather_location_query="$weather_city"
  fi

  if [ -z "$weather_location_query" ] && weather_fields_env_flag "${WEATHER_ALLOW_AUTO_GEOLOCATION:-false}"; then
    weather_fields_geolocate
  fi

  if [ -n "$weather_location_query" ]; then
    return 0
  fi
  if [ -n "$weather_city" ]; then
    weather_location_query="$weather_city"
  else
    weather_location_query="Paris"
  fi
}

weather_fields_geolocate() {
  local ipinfo_json=""
  local IFS=$'\t'

  ipinfo_json=$(curl -fsS --max-time "${WEATHER_REQUEST_TIMEOUT_SECONDS}" "https://ipinfo.io/json" 2>/dev/null)
  read -r weather_country weather_city weather_location_query < <(
    jq -r '[(.country // ""), (.city // ""), (.loc // .city // "")] | @tsv' <<<"$ipinfo_json" 2>/dev/null
  )

  [ "$weather_country" = "null" ] && weather_country=""
  [ "$weather_city" = "null" ] && weather_city=""
  [ "$weather_location_query" = "null" ] && weather_location_query=""
  return 0
}
