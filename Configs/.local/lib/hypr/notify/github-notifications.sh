#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/notify/github-notifications.lib.sh"

usage() {
  cat <<'USAGE'
Usage: hyprshell notify/github-notifications [--report]

Emit GitHub inbox and security-alert status.
  (default)   waybar JSON: text, tooltip, class
  --report    structured JSON for a panel
USAGE
}

report=0
while [ $# -gt 0 ]; do
  case "$1" in
    --report) report=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

ensure_github_notification_deps
load_github_notification_tokens
init_github_notification_state
collect_github_inbox_state
collect_github_security_state
if [ "$report" -eq 1 ]; then
  emit_github_notifications_report
else
  emit_github_notifications_status
fi
