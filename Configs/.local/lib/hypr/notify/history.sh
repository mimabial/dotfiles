#!/usr/bin/env bash
# Dunst state for the bar's notification panel: paused flag, counts and the
# history flattened out of dunst's {type,data} envelopes.
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell notify/history
Emit dunst's pause state, counts and notification history as JSON." "$@"

command -v dunstctl >/dev/null 2>&1 || { echo '{"paused":false,"waiting":0,"displayed":0,"entries":[]}'; exit 0; }

paused=false
[[ "$(dunstctl is-paused 2>/dev/null)" == "true" ]] && paused=true

counts="$(dunstctl count 2>/dev/null || true)"
field() { sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" <<<"${counts}" | head -n 1; }
waiting="$(field Waiting)"; displayed="$(field 'Currently displayed')"

# dunst timestamps are monotonic microseconds, so age comes from uptime
now_us="$(awk '{ printf "%d", $1 * 1000000 }' /proc/uptime)"

dunstctl history 2>/dev/null \
  | jq -c --argjson now "${now_us}" --argjson paused "${paused}" \
      --argjson waiting "${waiting:-0}" --argjson displayed "${displayed:-0}" '
    {paused: $paused, waiting: $waiting, displayed: $displayed,
     entries: [(.data[0] // [])[] | {
       id:      .id.data,
       app:     (.appname.data // ""),
       summary: (.summary.data // ""),
       body:    (.body.data // ""),
       urgency: (.urgency.data // "NORMAL"),
       age:     (($now - (.timestamp.data // $now)) / 1000000 | floor)
     }]}'
