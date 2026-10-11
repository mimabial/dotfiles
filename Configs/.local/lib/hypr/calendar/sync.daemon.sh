#!/usr/bin/env bash

set -euo pipefail

# Output is left unredirected so failures land in the service log; a failed tick
# is tolerated because the first one after login can beat Radicale to the port.

RADICALE_BOOKKEEPING='/\.Radicale\.(lock|cache|mtime|tmp-)'

config_value() {
  awk -v section="[$2]" -v key="$3" '
    $0 == section { inside = 1; next }
    /^\[/ { inside = 0 }
    inside && $1 == key { sub(/^[^=]*=[ \t]*/, ""); gsub(/"/, ""); print; exit }
  ' "$1"
}

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
local_calendars="$(config_value "${config_dir}/vdirsyncer/config" "storage personal_local" path)"
radicale_collections="$(config_value "${config_dir}/radicale/config" storage filesystem_folder)"

exec {storage_events}< <(exec inotifywait --monitor --recursive --format '%w%f' \
  --event close_write,create,delete,move --exclude "${RADICALE_BOOKKEEPING}" \
  "${local_calendars/#\~/${HOME}}" "${radicale_collections/#\~/${HOME}}" 2>&1)
storage_watcher_pid=$!
trap 'kill "${storage_watcher_pid}" 2>/dev/null' EXIT

while read -r -u "${storage_events}" line && [[ "${line}" != "Watches established." ]]; do :; done
vdirsyncer sync personal || true

while read -r -u "${storage_events}" _; do
  while read -t 0 -u "${storage_events}" && read -r -u "${storage_events}" _; do :; done
  vdirsyncer sync personal || true
done
exit 1
