capture_original_audio_state() {
  local -n original_ref=$2
  local sinks_payload sources_payload streams_payload

  sinks_payload=$(read_audio_endpoints_json sinks) || {
    echo "Could not read the current audio outputs" >&2
    return 1
  }
  sources_payload=$(read_audio_endpoints_json sources) || {
    echo "Could not read the current audio inputs" >&2
    return 1
  }
  original_ref[sink_states]=$(extract_card_endpoint_states "$1" "$sinks_payload" sinks) || {
    echo "Could not preserve the current output volume and mute state" >&2
    return 1
  }
  original_ref[source_states]=$(extract_card_endpoint_states "$1" "$sources_payload" sources) || {
    echo "Could not preserve the current input volume and mute state" >&2
    return 1
  }

  original_ref[stream_states]='[]'
  [[ ${original_ref[sink_states]} != '[]' ]] || return 0
  streams_payload=$(read_audio_endpoints_json sink-inputs) || {
    echo "Could not read the current audio streams" >&2
    return 1
  }
  original_ref[stream_states]=$(jq -ec --argjson sinks "${original_ref[sink_states]}" '
    ($sinks | map(.index)) as $sink_indexes
    | [
        .[]
        | select(.sink as $sink | $sink_indexes | index($sink))
        | {
            index: .index,
            mute: .mute,
            serial: ((.properties["object.serial"]
              // .properties["object.id"] // "") | tostring)
          }
      ]
    | select(all(.[];
        (.index | type) == "number"
        and (.mute | type) == "boolean"
        and (.serial | type) == "string"))
  ' <<<"$streams_payload") || {
    echo "Could not preserve the current audio stream mute state" >&2
    return 1
  }
}

mute_original_streams() {
  local -n original_ref=$1
  local index=''

  while read -r index; do
    hypr_daemon_call pactl set-sink-input-mute "$index" true >/dev/null 2>&1 || {
      echo "Could not mute the current audio streams" >&2
      return 1
    }
  done < <(jq -r '.[] | select(.mute == false) | .index' <<<"${original_ref[stream_states]}")
}
