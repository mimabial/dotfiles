VPN_LOCATION_TIMEOUT_SECONDS=5

vpn_fetch_location() {
  local url="https://ipinfo.io/json" token=""
  local token_file="${XDG_CONFIG_HOME:-$HOME/.config}/ipinfo.token"
  [[ ! -f "${token_file}" ]] || token="$(<"${token_file}")"
  token="${token//[[:space:]]/}"
  [[ -z "${token}" ]] || url="${url}?token=${token}"
  curl -fsS --max-time "${VPN_LOCATION_TIMEOUT_SECONDS}" "${url}" 2>/dev/null
}

vpn_geolocated_tooltip() {
  local title="$1" location_json="$2"
  jq -r --arg title "${title}" '"<b>" + $title + "</b>\nIP: " + .ip + "\n" + .city + ", " + .region + ", " + .country' <<<"${location_json}"
}

# Geolocation is a network round trip, so it is only attempted when the caller
# allows it; without it the tooltip falls back to the interface name alone.
vpn_set_connected_status_into() {
  local -n connected_status_ref="$1" connected_options_ref="$2"
  local label="$3" location_json=""
  connected_status_ref[provider_configured_or_detected]=true
  connected_status_ref[connection]=connected
  if [[ "${connected_options_ref[allow_geolocation]}" == true ]] && command -v curl >/dev/null 2>&1; then
    location_json="$(vpn_fetch_location)" || location_json=""
  fi
  if [[ -n "${location_json}" ]]; then
    connected_status_ref[tooltip]="$(vpn_geolocated_tooltip "${label}" "${location_json}")"
  elif [[ "${connected_options_ref[allow_geolocation]}" == true ]]; then
    connected_status_ref[tooltip]="<b>${label}</b>"$'\nConnected\nUnable to fetch IP info'
  else
    connected_status_ref[tooltip]="<b>${label}</b>"$'\nConnected\nLocation lookup disabled'
  fi
}
