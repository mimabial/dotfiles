#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell session/toggle-keep-awake
Toggle manual idle inhibition (keep the screen awake)." "$@"

source "${BASH_SOURCE[0]%/*}/idle/toggle.bash"

declare -A keep_awake_setting=(
  [enabled_fn]="idle_manual_enabled"
  [setter_fn]="idle_set_manual"
  [disabled_icon]="process-stop-symbolic"
  [enabled_icon]="system-run-symbolic"
  [disabled_summary]="Keep awake disabled"
  [enabled_summary]="Keep awake enabled"
  [disabled_body]="Idle behavior restored."
  [enabled_body]="Manual idle inhibition is active."
)
idle_toggle_setting keep_awake_setting
