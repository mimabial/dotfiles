#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

# Set a connected Bluetooth device's preferred audio mode.

address=${1:-}
profile=${2:-}

if (( $# != 2 )) || [[ ! $address =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ || -z $profile ]]; then
  echo "Usage: profile-set.sh <address> <profile>" >&2
  exit 1
fi

set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

card=$("$script_dir/profiles.sh" | jq -r --arg address "$address" --arg profile "$profile" '
  def normalized_address:
    ascii_downcase | gsub("[^0-9a-f]"; "");
  (.[($address | normalized_address)] // {})
  | select(any((.profiles // [])[]; .value == $profile))
  | .card // empty
')

[[ -n $card ]] || { echo "Bluetooth audio profile is not available" >&2; exit 1; }
# WirePlumber's device.restore-profile policy stores this profile against the
# individual BlueZ card and restores it the next time that device appears.
profile_set_pid=
cancel_profile_set() {
  trap - INT TERM HUP
  if [[ -n $profile_set_pid ]]; then
    kill -TERM "$profile_set_pid" >/dev/null 2>&1 || true
    wait "$profile_set_pid" >/dev/null 2>&1 || true
  fi
  exit 130
}
trap cancel_profile_set INT TERM HUP

"$script_dir/audio-profile-transition.sh" "$card" "$profile" &
profile_set_pid=$!
profile_set_status=0
wait "$profile_set_pid" || profile_set_status=$?
profile_set_pid=
trap - INT TERM HUP
(( profile_set_status == 0 )) || exit "$profile_set_status"

