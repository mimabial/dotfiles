#!/usr/bin/env bash

[ -f "$HOME/.cache/wal/colors-shell.sh" ] && source "$HOME/.cache/wal/colors-shell.sh"
# shellcheck source=/dev/null
source "$HOME/.local/lib/hypr/notify/github-notifications.lib.sh"

ensure_github_notification_deps
load_github_notification_tokens
init_github_notification_state
collect_github_inbox_state
collect_github_security_state
emit_github_notifications_status
