#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

(( $# == 0 )) || { echo "Usage: stream-route-status.sh" >&2; exit 1; }
set -o pipefail

metadata=$(timeout --kill-after=1s 2 pw-metadata -n default) || exit 1
sed -n "s/^update: id:\([0-9][0-9]*\) key:'target\.\(object\|node\)' value:'\([^']*\)'.*/\1\t\3/p" <<<"$metadata" |
  awk -F '\t' '$2 != "-1" { print $1 }' |
  jq -Rsc 'split("\n") | map(select(length > 0) | {key: ., value: true}) | from_entries'
