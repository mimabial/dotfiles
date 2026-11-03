#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell session/toggle-system-keep-awake
Toggle keeping the system running with the lid closed: lid close and idle still lock and blank the
screen, but never sleep." "$@"

source "${BASH_SOURCE[0]%/*}/idle/toggle.bash"

declare -A keep_awake_setting=(
  [enabled_fn]="idle_system_enabled"
  [setter_fn]="idle_set_system"
  [disabled_icon]="computer-symbolic"
  [enabled_icon]="computer-symbolic"
  [disabled_summary]="Lid keep running disabled"
  [enabled_summary]="Lid keep running enabled"
  [disabled_body]="Lid close and idle sleep again."
  [enabled_body]="Lid close and idle lock the session but never sleep."
)
idle_toggle_setting keep_awake_setting
