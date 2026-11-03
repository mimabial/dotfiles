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
  local -n weather_ref=$1
  [[ -f "$weather_location_cache_path" ]] || return 0
  weather_ref[country]=$(grep "^COUNTRY=" "$weather_location_cache_path" 2>/dev/null | cut -d'=' -f2-)
  weather_ref[city]=$(grep "^CITY=" "$weather_location_cache_path" 2>/dev/null | cut -d'=' -f2-)
}

weather_fields_resolve_location() {
  local -n weather_ref=$1
  local rc=0 coordinates=""

  if [ -n "${WEATHER_LOCATION:-}" ]; then
    weather_ref[city]="$WEATHER_LOCATION"
    weather_ref[location_query]="$WEATHER_LOCATION"
    return 0
  fi

  if coordinates="$(weather_fields_resolve_theme_coordinates)"; then
    weather_ref[location_query]="$coordinates"
    return 0
  else
    rc=$?
  fi
  if [ "${rc}" -gt 1 ]; then
    return "${rc}"
  fi

  if [ -z "${weather_ref[location_query]}" ]; then
    weather_fields_update_location_from_cache "$1"
    [ -n "${weather_ref[city]}" ] && weather_ref[location_query]="${weather_ref[city]}"
  fi

  if [ -z "${weather_ref[location_query]}" ] && weather_fields_env_flag "${WEATHER_ALLOW_AUTO_GEOLOCATION:-false}"; then
    weather_fields_geolocate "$1"
  fi

  if [ -n "${weather_ref[location_query]}" ]; then
    return 0
  fi
  if [ -n "${weather_ref[city]}" ]; then
    weather_ref[location_query]="${weather_ref[city]}"
  else
    weather_ref[location_query]="Paris"
  fi
}

weather_fields_geolocate() {
  local -n weather_ref=$1
  local ipinfo_json="" country="" city="" location_query=""
  local IFS=$'\t'

  ipinfo_json=$(curl -fsS --max-time "${WEATHER_REQUEST_TIMEOUT_SECONDS}" "https://ipinfo.io/json" 2>/dev/null)
  read -r country city location_query < <(
    jq -r '[(.country // ""), (.city // ""), (.loc // .city // "")] | @tsv' <<<"$ipinfo_json" 2>/dev/null
  )

  [ "$country" = "null" ] && country=""
  [ "$city" = "null" ] && city=""
  [ "$location_query" = "null" ] && location_query=""
  weather_ref[country]="$country"
  weather_ref[city]="$city"
  weather_ref[location_query]="$location_query"
  return 0
}
