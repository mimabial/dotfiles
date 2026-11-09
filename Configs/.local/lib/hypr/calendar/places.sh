#!/usr/bin/env bash
# Sends the query to one place search: ban (api-adresse.data.gouv.fr, French
# addresses) or photon (photon.komoot.io, OpenStreetMap, worldwide). Neither needs a key,
# and anything typed into the location field leaves the machine. Set CALENDAR_PLACES=0 to
# turn both off; the panel then falls back to the locations already used in your calendars.
set -euo pipefail

source_name="${1:-}"
query="${2:-}"
MIN_QUERY_LENGTH=3
PLACES_REQUESTED=8
PLACES_KEPT=3
MAX_PLACE_LENGTH=120
MAX_RESPONSE_BYTES=$((256 * 1024))
MAX_WAIT_SECONDS=10

emit_empty_places_and_exit() {
  printf '[]\n'
  exit 0
}

case "${source_name}" in
  ban)
    endpoint=https://api-adresse.data.gouv.fr/search/
    parameters=(--data-urlencode "autocomplete=1")
    labels='[ .features[]? | .properties.label // "" ]'
    ;;
  photon)
    lang="${LANG%%_*}"
    case "${lang}" in
      de | fr | it) ;;
      *) lang="en" ;;
    esac
    endpoint=https://photon.komoot.io/api/
    parameters=(--data-urlencode "lang=${lang}")
    labels='[ .features[]? | .properties | parts | dedupe | join(", ") ]'
    ;;
  *)
    printf 'Usage: %s {ban|photon} QUERY\n' "${0##*/}" >&2
    exit 2
    ;;
esac

[[ "${CALENDAR_PLACES:-1}" != "0" ]] || emit_empty_places_and_exit
[[ "${#query}" -ge "${MIN_QUERY_LENGTH}" ]] || emit_empty_places_and_exit
command -v curl >/dev/null 2>&1 || emit_empty_places_and_exit
command -v jq >/dev/null 2>&1 || emit_empty_places_and_exit

# A remote that accepts the connection and then says nothing would otherwise
# keep the panel waiting on it, and the reply is read into a shell that never
# restarts, so both the clock and the size are bounded.
response="$(
  curl -fsS --max-time "${MAX_WAIT_SECONDS}" --get \
    --data-urlencode "q=${query}" \
    --data-urlencode "limit=${PLACES_REQUESTED}" \
    "${parameters[@]}" \
    -A "hyprshell-calendar-places" \
    "${endpoint}" 2>/dev/null | head -c "${MAX_RESPONSE_BYTES}"
)" || emit_empty_places_and_exit

[[ -n "${response}" ]] || emit_empty_places_and_exit

printf '%s' "${response}" | jq -c --argjson kept "${PLACES_KEPT}" --argjson max_length "${MAX_PLACE_LENGTH}" '
  def parts:
    [ .name,
      ([.housenumber, .street] | map(select(. != null and . != "")) | join(" ")),
      (.city // .county), .country ]
    | map(select(. != null and . != ""));

  def dedupe:
    reduce .[] as $item ([];
      if any(.[]; ascii_downcase == ($item | ascii_downcase)) then . else . + [$item] end);

  '"${labels}"'
  | map(select(. != "") | .[0:$max_length])
  | dedupe
  | .[0:$kept]
' 2>/dev/null || emit_empty_places_and_exit
