#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell notify/history [LIMIT]
Emit dunst's pause state and counts with the archived notifications as JSON." "$@"

limit="${1:-200}"
[[ "${limit}" =~ ^[0-9]+$ ]] || limit=200

archive_cmd="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/notify/archive.sh"
snapshot="$("${archive_cmd}" snapshot "${limit}" 2>/dev/null || printf '{"entries":[],"unread":0,"seen":0}')"

paused=false
waiting=0
displayed=0

if command -v dunstctl >/dev/null 2>&1; then
  [[ "$(dunstctl is-paused 2>/dev/null)" == "true" ]] && paused=true
  counts="$(dunstctl count 2>/dev/null || true)"
  while IFS=: read -r key value; do
    case "${key}" in
      *Waiting) waiting="${value}" ;;
      *"Currently displayed") displayed="${value}" ;;
    esac
  done <<<"${counts}"
fi

jq -cn \
  --argjson paused "${paused}" \
  --argjson waiting "${waiting:-0}" \
  --argjson displayed "${displayed:-0}" \
  --argjson archive "${snapshot}" \
  '{paused: $paused, waiting: $waiting, displayed: $displayed,
    unread: $archive.unread, seen: $archive.seen, entries: $archive.entries}'
