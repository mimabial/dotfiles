surviving_stream_index() {
  jq -er --argjson index "$2" --arg serial "$3" '
    first(.[]
      | select((.index | type) == "number")
      | select(
          if $serial == "" then .index == $index
          else ((.properties["object.serial"]
            // .properties["object.id"] // "") | tostring) == $serial
          end)
      | .index) // empty
  ' <<<"$1"
}

restore_original_stream_mutes() {
  local -n original_ref=$1
  local current_streams index serial current_index failed=false

  [[ ${original_ref[stream_states]} != '[]' ]] || return 0
  current_streams=$(read_audio_endpoints_json sink-inputs) || return 1
  while read -r index serial; do
    current_index=$(surviving_stream_index "$current_streams" "$index" "$serial") || continue
    hypr_daemon_call pactl set-sink-input-mute "$current_index" false >/dev/null 2>&1 || failed=true
  done < <(jq -r '.[] | select(.mute == false) | [.index, .serial] | @tsv' <<<"${original_ref[stream_states]}")
  [[ $failed == false ]]
}

restore_saved_endpoint() {
  local kind=$1
  local endpoint_index=$2
  local saved_state=$3
  local new_state=$4
  local saved_count new_channel_count endpoint_muted
  local -a saved_volumes volume_arguments

  mapfile -t saved_volumes < <(jq -r '.volumes[]' <<<"$saved_state")
  saved_count=${#saved_volumes[@]}
  new_channel_count=$(jq '.volumes | length' <<<"$new_state") || return 1
  (( saved_count > 0 && new_channel_count > 0 )) || return 1
  if (( saved_count == new_channel_count )); then
    volume_arguments=("${saved_volumes[@]}")
  else
    volume_arguments=("${saved_volumes[0]}")
  fi
  hypr_daemon_call pactl "set-${kind}-volume" "$endpoint_index" \
    "${volume_arguments[@]}" >/dev/null 2>&1 || return 1
  endpoint_muted=$(jq -r '.mute' <<<"$saved_state") || return 1
  hypr_daemon_call pactl "set-${kind}-mute" "$endpoint_index" "$endpoint_muted" \
    >/dev/null 2>&1
}

restore_new_endpoint_states() {
  local kind=$1
  local old_states=$2
  local first_states=$3
  local current_states=$4
  local count position new_state saved_state endpoint_index initial_mute

  count=$(jq 'length' <<<"$current_states") || return 1
  for (( position = 0; position < count; position++ )); do
    new_state=$(jq -c --argjson position "$position" \
      '.[$position]' <<<"$current_states") || return 1
    endpoint_index=$(jq -r '.index' <<<"$new_state") || return 1
    saved_state=$(find_saved_endpoint_state "$old_states" "$new_state" "$position") || return 1

    if [[ -n $saved_state ]]; then
      restore_saved_endpoint "$kind" "$endpoint_index" "$saved_state" "$new_state" || return 1
      continue
    fi

    # A profile can expose a direction that did not exist before (A2DP ->
    # headset microphone, or off -> output). We changed only its mute bit, so
    # restore the value captured on first appearance and leave its own stored
    # volume untouched.
    initial_mute=$(first_seen_endpoint_mute "$first_states" "$new_state" "$position") || return 1
    if [[ $initial_mute == false ]]; then
      hypr_daemon_call pactl "set-${kind}-mute" "$endpoint_index" false \
        >/dev/null 2>&1 || return 1
    fi
  done
}

restore_topology_endpoints() {
  local -n original_ref=$1 topology_ref=$2
  local failed=false

  restore_new_endpoint_states sink "${original_ref[sink_states]}" \
    "${topology_ref[first_sink_states]}" "${topology_ref[sink_states]}" || failed=true
  restore_new_endpoint_states source "${original_ref[source_states]}" \
    "${topology_ref[first_source_states]}" "${topology_ref[source_states]}" || failed=true
  [[ $failed == false ]]
}

# A timed-out client can still have delivered the request. If the card is
# already back on the old profile, continue with endpoint restoration;
# otherwise this rollback genuinely failed.
revert_card_profile() {
  local -n card_ref=$1

  hypr_daemon_call pactl set-card-profile "${card_ref[name]}" "${card_ref[previous_profile]}" >/dev/null 2>&1 \
    || [[ $(read_card_active_profile "$1") == "${card_ref[previous_profile]}" ]]
}

rollback_profile() {
  local -n card_ref=$1 original_ref=$2 transition_ref=$3
  local -A restored=([sink_states]='[]' [source_states]='[]' [first_sink_states]='[]' [first_source_states]='[]')
  local original_sink_count original_source_count unused_failure

  [[ -n ${card_ref[previous_profile]} ]] || return 1
  restore_topology_endpoints "$2" "$3" || true
  read -r original_sink_count original_source_count < <(jq -nr \
    --argjson sinks "${original_ref[sink_states]}" --argjson sources "${original_ref[source_states]}" \
    '"\($sinks | length) \($sources | length)"')
  revert_card_profile "$1" || return 1
  wait_for_profile_topology "$1" "${card_ref[previous_profile]}" "$original_sink_count" "$original_source_count" \
    "${transition_ref[events_fd]}" restored unused_failure || return 1
  restore_topology_endpoints "$2" restored
}

cleanup_transition() {
  local status=$?
  local -n transition_ref=$3

  trap - EXIT
  if [[ ${transition_ref[change_requested]} == true && ${transition_ref[complete]} == false ]]; then
    rollback_profile "$1" "$2" "$3" \
      || echo "The previous audio profile could not be restored; audio endpoints may remain muted" >&2
  fi
  restore_original_stream_mutes "$2" \
    || echo "The previous audio stream state could not be fully restored" >&2
  kill "${transition_ref[events_pid]}" 2>/dev/null
  exit "$status"
}
