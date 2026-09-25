#!/usr/bin/env bash
# Sends the query to Photon (photon.komoot.io), an OpenStreetMap geocoder built
# for type-ahead and needing no API key. Anything typed into the location field
# therefore leaves the machine. Set CALENDAR_PLACES=0 to turn the lookup off;
# the panel then falls back to the locations already used in your calendars.
set -euo pipefail

query="${1:-}"

emit_empty_places_and_exit() {
  printf '[]\n'
  exit 0
}

[[ "${CALENDAR_PLACES:-1}" != "0" ]] || emit_empty_places_and_exit
[[ "${#query}" -ge 3 ]] || emit_empty_places_and_exit
command -v curl >/dev/null 2>&1 || emit_empty_places_and_exit
command -v jq >/dev/null 2>&1 || emit_empty_places_and_exit

lang="${LANG%%_*}"
case "${lang}" in
  de | fr | it) ;;
  *) lang="en" ;;
esac

# A remote that accepts the connection and then says nothing would otherwise
# keep the panel waiting on it, and the reply is read into a shell that never
# restarts, so both the clock and the size are bounded.
response="$(
  curl -fsS --max-time 4 --get \
    --data-urlencode "q=${query}" \
    --data-urlencode "limit=8" \
    --data-urlencode "lang=${lang}" \
    -A "hyprshell-calendar-places" \
    https://photon.komoot.io/api/ 2>/dev/null | head -c 262144
)" || emit_empty_places_and_exit

[[ -n "${response}" ]] || emit_empty_places_and_exit

printf '%s' "${response}" | jq -c '
  def parts:
    [ .name,
      ([.housenumber, .street] | map(select(. != null and . != "")) | join(" ")),
      (.city // .county), .country ]
    | map(select(. != null and . != ""));

  def dedupe:
    reduce .[] as $item ([];
      if any(.[]; ascii_downcase == ($item | ascii_downcase)) then . else . + [$item] end);

  [ .features[]? | .properties | parts | dedupe | join(", ") ]
  | map(select(. != "") | .[0:120])
  | dedupe
  | .[0:6]
' 2>/dev/null || emit_empty_places_and_exit
