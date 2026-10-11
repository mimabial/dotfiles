#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

if (( $# != 2 )) || [[ -z $1 || -z $2 ]]; then
  echo "Usage: hyprshell bluetooth/audio-profile-transition <card> <profile>" >&2
  exit 1
fi

set -o pipefail

AUDIO_MUTATION_LOCK_TIMEOUT_SECONDS=5

declare -A card=([name]=$1 [requested_profile]=$2)
declare -A original=()
declare -A transition=(
  [change_requested]=false [complete]=false
  [sink_states]='[]' [source_states]='[]' [first_sink_states]='[]' [first_source_states]='[]'
)

profile_lock=${XDG_RUNTIME_DIR:-/tmp}/hypr-audio-mutation-${UID}.lock
exec {audio_mutation_lock_fd}>>"$profile_lock" || {
  echo "Could not open the audio mutation lock" >&2
  exit 1
}
flock -w "$AUDIO_MUTATION_LOCK_TIMEOUT_SECONDS" "$audio_mutation_lock_fd" || {
  echo "Another audio change is still finishing" >&2
  exit 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "${script_dir}/lib/audio-endpoints.bash"
source "${script_dir}/lib/audio-profile-restoration.bash"
source "${script_dir}/lib/audio-profile-readiness.bash"
source "${script_dir}/lib/audio-profile-snapshot.bash"

requested_profile_metadata=$("$script_dir/audio-cards.sh" |
  jq -ec --arg card "${card[name]}" --arg profile "${card[requested_profile]}" '
    first(.[] | select(.name == $card) | .profiles[] | select(.value == $profile))
  ') || {
  echo "Profile is not available for this device" >&2
  exit 1
}

expected_sinks=$(jq -r '.sinks // 0' <<<"$requested_profile_metadata")
expected_sources=$(jq -r '.sources // 0' <<<"$requested_profile_metadata")
[[ $expected_sinks =~ ^[0-9]+$ && $expected_sources =~ ^[0-9]+$ ]] || exit 1

card_info=$(hypr_daemon_call pactl -f json list cards 2>/dev/null |
  jq -ec --arg card "${card[name]}" 'first(.[] | select(.name == $card))') || {
  echo "Audio card is not available" >&2
  exit 1
}
card[index]=$(jq -r '.index // empty' <<<"$card_info") || exit 1
[[ ${card[index]} =~ ^[0-9]+$ ]] || exit 1

# Re-applying the active profile needlessly tears down the same endpoints,
# briefly silences playback, and creates another opportunity for restoration
# to fail. The caller can still persist this already-active preference.
card[previous_profile]=$(jq -r '.active_profile // empty' <<<"$card_info") || exit 1
[[ ${card[previous_profile]} != "${card[requested_profile]}" ]] || exit 0

capture_original_audio_state card original || exit 1

exec {audio_events_fd}< <(exec pactl subscribe 2>/dev/null)
transition[events_pid]=$!
transition[events_fd]=$audio_events_fd

trap 'cleanup_transition card original transition' EXIT

mute_original_streams original || exit 1

transition[change_requested]=true
hypr_daemon_call pactl set-card-profile "${card[name]}" "${card[requested_profile]}" || exit 1

if ! wait_for_profile_topology card "${card[requested_profile]}" "$expected_sinks" "$expected_sources" \
    "${transition[events_fd]}" transition transition_error; then
  echo "$transition_error" >&2
  exit 1
fi

if ! restore_new_endpoint_states sink "${original[sink_states]}" \
  "${transition[first_sink_states]}" "${transition[sink_states]}"; then
  echo "Could not restore the new audio output state" >&2
  exit 1
fi
if ! restore_new_endpoint_states source "${original[source_states]}" \
  "${transition[first_source_states]}" "${transition[source_states]}"; then
  echo "Could not restore the new audio input state" >&2
  exit 1
fi

if ! restore_original_stream_mutes original; then
  echo "Could not restore the previous audio stream state" >&2
  exit 1
fi
transition[complete]=true
trap - EXIT
kill "${transition[events_pid]}" 2>/dev/null
