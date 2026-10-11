#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell session/toggle-fullscreen-keep-awake
Toggle keeping the system awake for fullscreen apps and games." "$@"

source "${BASH_SOURCE[0]%/*}/idle/toggle.bash"

declare -A keep_awake_setting=(
  [enabled_fn]="idle_fullscreen_enabled"
  [setter_fn]="idle_set_fullscreen"
  [disabled_icon]="view-restore-symbolic"
  [enabled_icon]="view-fullscreen-symbolic"
  [disabled_summary]="Fullscreen and game keep awake disabled"
  [enabled_summary]="Fullscreen and game keep awake enabled"
)
idle_toggle_setting keep_awake_setting
