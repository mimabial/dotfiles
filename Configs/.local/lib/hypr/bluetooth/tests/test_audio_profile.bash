#!/usr/bin/env bash
set -euo pipefail

BT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)"
SCRIPT="${BT_DIR}/audio-profile-transition.sh"

# The script runs a transition when sourced, so pull just the functions under
# test out of it; extracting by name keeps the test from drifting off the real one.
extract() { awk -v fn="$1" '$0 ~ "^"fn"\\(\\) \\{" {p=1} p {print; if ($0 == "}") exit}' "${SCRIPT}"; }
eval "$(extract mute_new_endpoints)"
eval "$(extract endpoints_restored)"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

states() {  # index name serial muted -> one endpoint as a json array
  jq -cn --argjson i "$1" --arg n "$2" --arg s "$3" --argjson m "$4" \
    '[{index:$i, name:$n, serial:$s, mute:$m}]'
}

test_unmuted_endpoint_gets_muted() {
  local calls=""
  pactl() { calls+="$* "; }
  local -A seen=()
  mute_new_endpoints sink "$(states 5 alsa_out front 'false')" seen || fail "returned nonzero"
  [[ "${calls}" == *"set-sink-mute 5 true"* ]] || fail "sink was not muted: ${calls}"
  [[ ${seen["5:n:$(printf alsa_out | base64):s:$(printf front | base64)"]+x} == x ]] \
    || fail "endpoint not recorded as seen"
}

test_already_muted_is_recorded_not_muted_again() {
  local calls=""
  pactl() { calls+="$* "; }
  local -A seen=()
  mute_new_endpoints sink "$(states 5 alsa_out front 'true')" seen || fail "returned nonzero"
  [[ -z "${calls}" ]] || fail "should not have called pactl: ${calls}"
  [[ ${#seen[@]} -eq 1 ]] || fail "already-muted endpoint must still be recorded"
}

test_seen_endpoint_is_skipped() {
  local calls=""
  pactl() { calls+="$* "; }
  local -A seen=(["5:n:$(printf alsa_out | base64):s:$(printf front | base64)"]=true)
  mute_new_endpoints sink "$(states 5 alsa_out front 'false')" seen || fail "returned nonzero"
  [[ -z "${calls}" ]] || fail "already-seen endpoint must not be re-muted: ${calls}"
}

test_source_kind_uses_source_command() {
  local calls=""
  pactl() { calls+="$* "; }
  local -A seen=()
  mute_new_endpoints source "$(states 2 alsa_in mic 'false')" seen || fail "returned nonzero"
  [[ "${calls}" == *"set-source-mute 2 true"* ]] || fail "wrong pactl subcommand: ${calls}"
}

test_pactl_failure_propagates() {
  pactl() { return 1; }
  local -A seen=()
  if mute_new_endpoints sink "$(states 5 alsa_out front 'false')" seen; then
    fail "a failed mute must abort the rollback"
  fi
}

test_endpoints_restored() {
  endpoints_restored 0 0 || fail "0 expected / 0 present is restored"
  ! endpoints_restored 0 1 || fail "0 expected / 1 present is not restored"
  ! endpoints_restored 2 1 || fail "2 expected / 1 present is not restored"
  endpoints_restored 2 2 || fail "2 expected / 2 present is restored"
  endpoints_restored 2 3 || fail "2 expected / 3 present is restored"
}

# `timeout` wraps the real pactl in the function under test; stub it to run the
# stubbed pactl instead of the binary.
timeout() { while [[ "$1" == -* || "$1" == [0-9]* ]]; do shift; done; "$@"; }

test_unmuted_endpoint_gets_muted
test_already_muted_is_recorded_not_muted_again
test_seen_endpoint_is_skipped
test_source_kind_uses_source_command
test_pactl_failure_propagates
test_endpoints_restored

eval "$(extract endpoint_signature)"

# Two reads of one topology must compare equal however pactl ordered them, and
# any change of membership or identity must not.
test_signature_is_order_independent() {
  # same index, different names: only a full sort makes these two reads equal
  local one='[{"index":1,"name":"a","serial":"s1","mute":false},{"index":1,"name":"b","serial":"s2","mute":false}]'
  local rev='[{"index":1,"name":"b","serial":"s2","mute":true},{"index":1,"name":"a","serial":"s1","mute":true}]'
  [[ "$(endpoint_signature "$one" '[]')" == "$(endpoint_signature "$rev" '[]')" ]] \
    || fail "reordering or mute state must not change the signature"
}

test_signature_uses_full_identity() {
  local a='[{"index":1,"name":"x","serial":"s1"}]'
  [[ "$(endpoint_signature "$a" '[]')" != "$(endpoint_signature '[{"index":1,"name":"x","serial":"s2"}]' '[]')" ]] \
    || fail "serial must be part of the identity"
  [[ "$(endpoint_signature "$a" '[]')" != "$(endpoint_signature '[{"index":1,"name":"z","serial":"s1"}]' '[]')" ]] \
    || fail "name must be part of the identity"
  [[ "$(endpoint_signature "$a" '[]')" != "$(endpoint_signature '[{"index":2,"name":"x","serial":"s1"}]' '[]')" ]] \
    || fail "index must be part of the identity"
}

test_signature_detects_new_endpoint() {
  local a='[{"index":1,"name":"x","serial":"s1"}]'
  local b='[{"index":1,"name":"x","serial":"s1"},{"index":2,"name":"y","serial":"s2"}]'
  [[ "$(endpoint_signature "$a" '[]')" != "$(endpoint_signature "$b" '[]')" ]] \
    || fail "a new endpoint must change the signature"
}

# Distinct sink and source sets must stay distinct in the result, so reading one
# from the other cannot go unnoticed.
test_signature_keeps_sinks_and_sources_apart() {
  local sinks='[{"index":1,"name":"out","serial":"s1"}]'
  local sources='[{"index":9,"name":"in","serial":"s9"}]'
  [[ "$(endpoint_signature "$sinks" "$sources")" != "$(endpoint_signature "$sinks" "$sinks")" ]] \
    || fail "sources must come from the source set"
  [[ "$(endpoint_signature "$sinks" '[]')" != "$(endpoint_signature '[]' "$sinks")" ]] \
    || fail "a sink and a source must not produce the same signature"
}

test_signature_is_order_independent
test_signature_uses_full_identity
test_signature_detects_new_endpoint
test_signature_keeps_sinks_and_sources_apart
