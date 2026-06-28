#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell session/toggle-keep-awake
Toggle manual idle inhibition (keep the screen awake)." "$@"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/idle.state.sh"

idle_toggle_state \
  idle_manual_enabled \
  idle_set_manual \
  0 \
  "process-stop-symbolic" \
  "Keep awake disabled" \
  1 \
  "system-run-symbolic" \
  "Keep awake enabled" \
  "Idle behavior restored." \
  "Manual idle inhibition is active."
