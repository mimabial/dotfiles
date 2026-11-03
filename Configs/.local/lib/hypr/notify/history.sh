#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell notify/history [LIMIT]
Emit dunst's pause state and counts with the archived notifications as JSON." "$@"

archive_cmd="${HYPR_LIB_DIR}/notify/archive.sh"
snapshot="$("${archive_cmd}" snapshot "${1:-}" 2>/dev/null || printf '{"entries":[],"unread":0,"seen":0}')"

paused=false
waiting=0
displayed=0

while read -r property _ _ value; do
  case "${property}" in
    paused) paused="${value}" ;;
    waitingLength) waiting="${value}" ;;
    displayedLength) displayed="${value}" ;;
  esac
done < <(dbus-send --session --print-reply=literal --dest=org.freedesktop.Notifications /org/freedesktop/Notifications \
  org.freedesktop.DBus.Properties.GetAll string:org.dunstproject.cmd0 2>/dev/null)

jq -cn \
  --argjson verification "$(python3 "${HYPR_LIB_DIR}/notify/verification.py" list)" \
  --argjson paused "${paused}" \
  --argjson waiting "${waiting:-0}" \
  --argjson displayed "${displayed:-0}" \
  --argjson archive "${snapshot}" \
  '{paused: $paused, waiting: $waiting, displayed: $displayed, verification: $verification,
    unread: $archive.unread, seen: $archive.seen, entries: $archive.entries}'
