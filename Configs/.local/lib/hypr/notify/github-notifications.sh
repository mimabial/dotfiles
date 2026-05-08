#!/usr/bin/env bash

set -euo pipefail

[ -f "${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors-shell.sh" ] && source "${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors-shell.sh"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/notify/github-notifications.lib.sh"

ensure_github_notification_deps
load_github_notification_tokens
init_github_notification_state
collect_github_inbox_state
collect_github_security_state
emit_github_notifications_status
