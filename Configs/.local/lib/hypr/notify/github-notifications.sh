#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/notify/github-notifications.lib.sh"

usage() {
  cat <<'USAGE'
Usage: hyprshell notify/github-notifications [--report | --mark-read ID...]

Emit GitHub inbox and security-alert status.
  (default)          bar JSON: text, tooltip, class
  --report           structured JSON for a panel
  --mark-read ID...  mark notification threads read
USAGE
}

mode=status
mark_ids=()
while [ $# -gt 0 ]; do
  case "$1" in
    --report) mode=report ;;
    --mark-read) mode=mark ;;
    -h | --help) usage; exit 0 ;;
    *)
      [ "$mode" = mark ] && [[ "$1" =~ ^[0-9]+$ ]] || { usage >&2; exit 2; }
      mark_ids+=("$1")
      ;;
  esac
  shift
done
[ "$mode" != mark ] || [ "${#mark_ids[@]}" -gt 0 ] || { usage >&2; exit 2; }

ensure_github_notification_deps
load_github_notification_tokens
if [ "$mode" = mark ]; then
  mark_github_notifications_read "${mark_ids[@]}"
  exit
fi
init_github_notification_state
collect_github_inbox_state
collect_github_security_state
if [ "$mode" = report ]; then
  collect_github_review_requests
  emit_github_notifications_report
else
  emit_github_notifications_status
fi
