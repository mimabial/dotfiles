#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

direction=${1:-}
stream=${2:-}
target=${3:-}
mode=${4:-}

if (( $# != 4 )) || [[ $direction != playback && $direction != recording ]] ||
  [[ ! $stream =~ ^[0-9]+$ || ! $target =~ ^[0-9]+$ ]] ||
  [[ $mode != override && $mode != default ]]; then
  echo "Usage: stream-route.sh <playback|recording> <stream-serial> <target-serial> <override|default>" >&2
  exit 1
fi

set -o pipefail

if [[ $direction == playback ]]; then
  move_command=move-sink-input
  streams_key=sink_inputs
  targets_key=sinks
else
  move_command=move-source-output
  streams_key=source_outputs
  targets_key=sources
fi

state=$(timeout --kill-after=1s 2 pactl -f json list) || exit 1
ids=$(jq -er --arg stream "$stream" --arg target "$target" \
  --arg streams "$streams_key" --arg targets "$targets_key" '
  (.[$streams] // [] | map(select((.index | tostring) == $stream))[0].properties."object.id") as $stream_id
  | (.[$targets] // [] | map(select((.index | tostring) == $target))[0].properties."object.id") as $target_id
  | select(($stream_id | tostring | test("^[0-9]+$")) and ($target_id | tostring | test("^[0-9]+$")))
  | [$stream_id, $target_id] | @tsv
' <<<"$state") || {
  echo "The stream or audio device is no longer available" >&2
  exit 1
}
read -r stream_id target_id <<<"$ids"

timeout --kill-after=1s 2 pactl "$move_command" "$stream" "$target" || exit 1

if [[ $mode == override ]]; then
  timeout --kill-after=1s 2 pw-metadata -n default -- "$stream_id" target.object "$target" Spa:Id >/dev/null || exit 1
  timeout --kill-after=1s 2 pw-metadata -n default -- "$stream_id" target.node "$target_id" Spa:Id >/dev/null || exit 1
else
  timeout --kill-after=1s 2 pw-metadata -n default -- "$stream_id" target.object -1 Spa:Id >/dev/null || exit 1
  timeout --kill-after=1s 2 pw-metadata -n default -- "$stream_id" target.node -1 Spa:Id >/dev/null || exit 1
fi
