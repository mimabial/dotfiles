#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell session/toggle-audio-keep-awake
Toggle keeping the system awake while audio is playing." "$@"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/idle.state.sh"

idle_toggle_state \
  idle_audio_enabled \
  idle_set_audio \
  0 \
  "audio-speakers-symbolic" \
  "Audio keep awake disabled" \
  1 \
  "audio-speakers-symbolic" \
  "Audio keep awake enabled"
