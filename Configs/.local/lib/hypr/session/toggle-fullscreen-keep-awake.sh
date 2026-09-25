#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell session/toggle-fullscreen-keep-awake
Toggle keeping the system awake for fullscreen apps and games." "$@"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/idle.state.sh"

idle_toggle_state \
  idle_fullscreen_enabled \
  idle_set_fullscreen \
  0 \
  "view-restore-symbolic" \
  "Fullscreen and game keep awake disabled" \
  1 \
  "view-fullscreen-symbolic" \
  "Fullscreen and game keep awake enabled"
