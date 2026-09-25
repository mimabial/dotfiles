#!/usr/bin/env bash

set -euo pipefail

# Only the personal pair: the holidays feed is a remote .ics that changes once a
# year, so pacing it with the todo loop would refetch it from Google needlessly.
#
# Output is left unredirected so failures land in the service log; a failed tick
# is tolerated because the first one after login can beat Radicale to the port.

SYNC_INTERVAL_SECONDS="${CALDAV_SYNC_INTERVAL:-900}"
[[ "${SYNC_INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] && ((SYNC_INTERVAL_SECONDS > 0)) || SYNC_INTERVAL_SECONDS=900

while :; do
  vdirsyncer sync personal || true
  sleep "${SYNC_INTERVAL_SECONDS}"
done
