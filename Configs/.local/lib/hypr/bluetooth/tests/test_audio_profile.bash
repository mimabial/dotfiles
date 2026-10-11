#!/usr/bin/env bash
set -euo pipefail

BT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)"
source "${BT_DIR}/lib/audio-endpoints.bash"
source "${BT_DIR}/lib/audio-profile-readiness.bash"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

single_endpoint_states() {
  jq -cn --argjson index "$1" --arg name "$2" --arg serial "$3" --argjson mute "$4" \
    '[{$index, $name, $serial, $mute}]'
}

test_unmuted_endpoint_gets_muted() {
  local calls=""
  pactl() { calls+="$* "; }
  local -A seen=()
  mute_new_endpoints sink "$(single_endpoint_states 5 alsa_out front 'false')" seen || fail "returned nonzero"
  [[ "${calls}" == *"set-sink-mute 5 true"* ]] || fail "sink was not muted: ${calls}"
  [[ ${seen["5:n:$(printf alsa_out | base64):s:$(printf front | base64)"]+x} == x ]] \
    || fail "endpoint not recorded as seen"
}

test_already_muted_is_recorded_not_muted_again() {
  local calls=""
  pactl() { calls+="$* "; }
  local -A seen=()
  mute_new_endpoints sink "$(single_endpoint_states 5 alsa_out front 'true')" seen || fail "returned nonzero"
  [[ -z "${calls}" ]] || fail "should not have called pactl: ${calls}"
  [[ ${#seen[@]} -eq 1 ]] || fail "already-muted endpoint must still be recorded"
}

test_seen_endpoint_is_skipped() {
  local calls=""
  pactl() { calls+="$* "; }
  local -A seen=(["5:n:$(printf alsa_out | base64):s:$(printf front | base64)"]=true)
  mute_new_endpoints sink "$(single_endpoint_states 5 alsa_out front 'false')" seen || fail "returned nonzero"
  [[ -z "${calls}" ]] || fail "already-seen endpoint must not be re-muted: ${calls}"
}

test_source_kind_uses_source_command() {
  local calls=""
  pactl() { calls+="$* "; }
  local -A seen=()
  mute_new_endpoints source "$(single_endpoint_states 2 alsa_in mic 'false')" seen || fail "returned nonzero"
  [[ "${calls}" == *"set-source-mute 2 true"* ]] || fail "wrong pactl subcommand: ${calls}"
}

test_pactl_failure_propagates() {
  pactl() { return 1; }
  local -A seen=()
  if mute_new_endpoints sink "$(single_endpoint_states 5 alsa_out front 'false')" seen; then
    fail "a failed mute must abort the rollback"
  fi
}

test_endpoint_count_is_ready() {
  endpoint_count_is_ready 0 0 0 || fail "0 expected / 0 present is restored"
  ! endpoint_count_is_ready 0 1 1 || fail "0 expected / 1 present is not restored"
  ! endpoint_count_is_ready 2 1 1 || fail "2 expected / 1 present is not restored"
  endpoint_count_is_ready 2 2 2 || fail "2 expected / 2 present is restored"
  endpoint_count_is_ready 2 3 3 || fail "2 expected / 3 present is restored"
}

test_loopback_never_holds_an_old_endpoint() {
  endpoint_count_is_ready 0 1 0 || fail "a lone loopback must not count as an old input"
  ! endpoint_count_is_ready 0 2 1 || fail "a real endpoint beside the loopback is still an old input"
  endpoint_count_is_ready 1 1 0 || fail "the loopback can be the new profile's input"
}

test_card_events_wake_the_wait() {
  audio_event_affects_card 7 "Event 'change' on card #7" || fail "a change on the card must wake the wait"
  audio_event_affects_card 7 "Event 'new' on sink #9" || fail "a new sink must wake the wait"
  audio_event_affects_card 7 "Event 'remove' on source #9" || fail "a removed source must wake the wait"
  ! audio_event_affects_card 7 "Event 'change' on card #70" || fail "another card must not wake the wait"
  ! audio_event_affects_card 7 "Event 'change' on sink-input #3" || fail "stream changes must not wake the wait"
  ! audio_event_affects_card 7 "Event 'new' on sink-input #3" || fail "new streams must not wake the wait"
}

# hypr_daemon_call wraps the real pactl in the function under test; stub it to run
# the stubbed pactl instead of the binary.
hypr_daemon_call() { "$@"; }

test_unmuted_endpoint_gets_muted
test_already_muted_is_recorded_not_muted_again
test_seen_endpoint_is_skipped
test_source_kind_uses_source_command
test_pactl_failure_propagates
test_endpoint_count_is_ready
test_loopback_never_holds_an_old_endpoint
test_card_events_wake_the_wait

