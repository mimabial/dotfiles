# PipeWire's PulseAudio compatibility layer may omit the legacy top-level
# `card` field from sink/source JSON. `device.name` is the stable association in
# that schema, while native PulseAudio still exposes the numeric card index.
CARD_ENDPOINT_FILTER='
  def belongs_to_card($card_index; $card_name):
    ((.card // -1) == $card_index)
    or ((.properties["device.name"] // "") == $card_name);
  .[] | select(belongs_to_card($card_index; $card_name))
'
declare -gA CARD_ENDPOINT_FILTER_BY_KIND=(
  [sinks]="$CARD_ENDPOINT_FILTER"
  [sources]="$CARD_ENDPOINT_FILTER
    | select((.monitor_source // \"\") == \"\")
    | select(((.name // \"\") | endswith(\".monitor\")) | not)"
)

read_audio_endpoints_json() {
  local kind=$1
  local payload

  payload=$(hypr_daemon_call pactl -f json list "$kind" 2>/dev/null) || return 1
  jq -e 'type == "array"' <<<"$payload" >/dev/null || return 1
  printf '%s\n' "$payload"
}

read_card_active_profile() {
  local -n card_ref=$1
  local payload

  payload=$(hypr_daemon_call pactl -f json list cards 2>/dev/null) || return 1
  jq -er --arg card "${card_ref[name]}" '
    first(.[] | select(.name == $card) | .active_profile) // empty
  ' <<<"$payload"
}

extract_card_endpoint_states() {
  local -n card_ref=$1
  local payload=$2
  local kind=$3

  jq -ec --argjson card_index "${card_ref[index]}" --arg card_name "${card_ref[name]}" "
    [${CARD_ENDPOINT_FILTER_BY_KIND[$kind]} | {
      index: .index,
      name: (.name // \"\"),
      serial: ((.properties[\"object.serial\"]
        // .properties[\"object.id\"] // \"\") | tostring),
      mute: .mute,
      profile_bound: (.properties[\"bluez5.loopback\"] != \"true\"),
      volumes: [
        (.volume // {}) | to_entries[]?
        | (.value.value_percent
          // (if .value.value != null then (.value.value | tostring) else empty end))
      ]
    }]
    | select(all(.[];
        (.index | type) == \"number\"
        and (.name | type) == \"string\"
        and (.serial | type) == \"string\"
        and (.mute | type) == \"boolean\"
        and (.volumes | length) > 0
        and all(.volumes[]; type == \"string\" and length > 0)))
  " <<<"$payload"
}

merge_first_seen_endpoint_states() {
  jq -cn --argjson seen "$1" --argjson current "$2" '
    def endpoint_key:
      if .serial != "" then "serial:" + .serial
      elif .name != "" then "name:" + .name
      else "index:" + (.index | tostring) end;
    $seen + [
      $current[] as $candidate
      | select(($seen | map(endpoint_key)
          | index($candidate | endpoint_key)) == null)
      | $candidate
    ]
  '
}

find_saved_endpoint_state() {
  jq -cn --argjson old "$1" --argjson current "$2" --argjson position "$3" '
    ([$old[]
      | select($current.serial != "" and .serial == $current.serial)][0]
      // [$old[]
        | select($current.name != "" and .name == $current.name)][0]
      // $old[$position]
      // empty)
  '
}

first_seen_endpoint_mute() {
  jq -r --argjson current "$2" --argjson position "$3" '
    ([.[] | select($current.serial != "" and .serial == $current.serial)][0]
      // [.[] | select($current.name != "" and .name == $current.name)][0]
      // .[$position]
      // null) as $initial
    | if ($initial | type) == "object" and ($initial.mute | type) == "boolean"
      then $initial.mute else empty end
  ' <<<"$1"
}

current_endpoint_states() {
  local kind=$2
  local payload states

  payload=$(read_audio_endpoints_json "$kind") || payload='[]'
  states=$(extract_card_endpoint_states "$1" "$payload" "$kind") || states='[]'
  printf '%s\n' "$states"
}
