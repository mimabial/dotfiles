AUDIO_ENDPOINT_EVENT="^Event '(new|remove)' on (sink|source) #"
SETTLE_TIMEOUT_MS=2500

mute_new_endpoints() {
  local kind="$1"
  local states="$2"
  local -n seen_ref="$3"
  local index="" identity="" muted="" key=""

  while read -r index identity muted; do
    key="${index}:${identity}"
    [[ ${seen_ref[$key]+present} ]] && continue
    if [[ $muted == false ]]; then
      hypr_daemon_call pactl "set-${kind}-mute" "$index" true >/dev/null 2>&1 || return 1
    fi
    seen_ref[$key]=true
  done < <(jq -r '.[] | [
      .index,
      ("n:" + (.name | @base64) + ":s:" + (.serial | @base64)),
      .mute
    ] | @tsv' <<<"$states")
}

endpoint_count_is_ready() {
  local expected="$1"
  local count="$2"
  local profile_bound="$3"

  (( expected == 0 )) && { (( profile_bound == 0 )); return; }
  (( count >= expected ))
}

audio_event_affects_card() {
  local card_index=$1 event=$2

  [[ $event =~ $AUDIO_ENDPOINT_EVENT || $event == *" on card #${card_index}" ]]
}

drain_queued_card_events() {
  local events_fd=$1 card_index=$2 event='' queued=1

  while read -t 0 -u "$events_fd" && read -r -u "$events_fd" event; do
    audio_event_affects_card "$card_index" "$event" && queued=0
  done
  return "$queued"
}

await_card_event() {
  local events_fd=$1 card_index=$2 deadline_ms=$3 remaining_ms timeout_s event=''

  while remaining_ms=$(( deadline_ms - ${EPOCHREALTIME//[!0-9]/} / 1000 )); (( remaining_ms > 0 )); do
    printf -v timeout_s '%d.%03d' $(( remaining_ms / 1000 )) $(( remaining_ms % 1000 ))
    read -r -t "$timeout_s" -u "$events_fd" event || return 1
    audio_event_affects_card "$card_index" "$event" && return 0
  done
  return 1
}

wait_for_profile_topology() {
  local -n card_ref=$1 topology_ref=$6 failure_ref=$7
  local target_profile=$2 expected_sinks=$3 expected_sources=$4 events_fd=$5
  local deadline_ms reported_profile=''
  local sink_count=0 sink_bound=0 source_count=0 source_bound=0
  local -A muted_sinks=() muted_sources=()

  deadline_ms=$(( ${EPOCHREALTIME//[!0-9]/} / 1000 + SETTLE_TIMEOUT_MS ))
  while :; do
    topology_ref[sink_states]=$(current_endpoint_states "$1" sinks)
    topology_ref[source_states]=$(current_endpoint_states "$1" sources)
    reported_profile=$(read_card_active_profile "$1") || reported_profile=
    topology_ref[first_sink_states]=$(merge_first_seen_endpoint_states \
      "${topology_ref[first_sink_states]}" "${topology_ref[sink_states]}") \
      || { failure_ref="Could not track the new audio output state"; return 1; }
    topology_ref[first_source_states]=$(merge_first_seen_endpoint_states \
      "${topology_ref[first_source_states]}" "${topology_ref[source_states]}") \
      || { failure_ref="Could not track the new audio input state"; return 1; }

    mute_new_endpoints sink "${topology_ref[sink_states]}" muted_sinks \
      || { failure_ref="Could not mute the new audio output"; return 1; }
    mute_new_endpoints source "${topology_ref[source_states]}" muted_sources \
      || { failure_ref="Could not mute the new audio input"; return 1; }

    read -r sink_count sink_bound source_count source_bound < <(jq -nr \
      --argjson sinks "${topology_ref[sink_states]}" --argjson sources "${topology_ref[source_states]}" \
      '[$sinks, $sources] | map(length, (map(select(.profile_bound)) | length)) | join(" ")')
    if [[ $reported_profile == "$target_profile" ]] \
        && endpoint_count_is_ready "$expected_sinks" "$sink_count" "$sink_bound" \
        && endpoint_count_is_ready "$expected_sources" "$source_count" "$source_bound"; then
      drain_queued_card_events "$events_fd" "${card_ref[index]}" || return 0
      (( ${EPOCHREALTIME//[!0-9]/} / 1000 < deadline_ms )) || break
    else
      await_card_event "$events_fd" "${card_ref[index]}" "$deadline_ms" || break
    fi
  done

  if [[ $reported_profile != "$target_profile" ]]; then
    failure_ref="The new audio profile did not become active"
  elif (( expected_sinks == 0 && sink_bound != 0 )); then
    failure_ref="The previous audio output did not disappear"
  elif (( sink_count < expected_sinks )); then
    failure_ref="The new audio output did not become available"
  elif (( expected_sources == 0 && source_bound != 0 )); then
    failure_ref="The previous audio input did not disappear"
  elif (( source_count < expected_sources )); then
    failure_ref="The new audio input did not become available"
  else
    failure_ref="The new audio endpoints did not settle"
  fi
  return 1
}
