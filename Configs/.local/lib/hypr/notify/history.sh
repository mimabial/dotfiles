#!/usr/bin/env bash
# Everything the notification panel draws in one payload: dunst's live pause
# state and counts, plus the archive (notify/archive) that outlives dunst's
# 20-entry ring.
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell notify/history [LIMIT]
Emit dunst's pause state and counts with the archived notifications as JSON." "$@"

limit="${1:-200}"
[[ "${limit}" =~ ^[0-9]+$ ]] || limit=200

archive_cmd="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/notify/archive.sh"
entries="$("${archive_cmd}" list "${limit}" 2>/dev/null || printf '[]')"
unread="$("${archive_cmd}" unread 2>/dev/null | jq -r '.unread // 0' 2>/dev/null || echo 0)"
seen="$("${archive_cmd}" seen 2>/dev/null | jq -r '.seen // 0' 2>/dev/null || echo 0)"

paused=false
waiting=0
displayed=0

if command -v dunstctl >/dev/null 2>&1; then
  [[ "$(dunstctl is-paused 2>/dev/null)" == "true" ]] && paused=true
  counts="$(dunstctl count 2>/dev/null || true)"
  field() { sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" <<<"${counts}" | head -n 1; }
  waiting="$(field Waiting)"
  displayed="$(field 'Currently displayed')"
fi

jq -cn \
  --argjson paused "${paused}" \
  --argjson waiting "${waiting:-0}" \
  --argjson displayed "${displayed:-0}" \
  --argjson unread "${unread:-0}" \
  --argjson seen "${seen:-0}" \
  --argjson entries "${entries}" \
  '{paused: $paused, waiting: $waiting, displayed: $displayed,
    unread: $unread, seen: $seen, entries: $entries}'
