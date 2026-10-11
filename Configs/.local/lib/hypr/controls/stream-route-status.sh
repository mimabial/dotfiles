#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/controls/lib/audio-streams.bash" || exit 1

(( $# == 0 )) || { echo "Usage: stream-route-status.sh" >&2; exit 1; }
set -o pipefail

metadata=$(hypr_daemon_call pw-metadata -n default) || exit 1
streams_with_explicit_target <<<"$metadata" |
  jq -Rsc 'split("\n") | map(select(length > 0) | {key: ., value: true}) | from_entries'
