#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell session/toggle-audio-keep-awake
Toggle keeping the system awake while audio is playing." "$@"

source "${BASH_SOURCE[0]%/*}/idle/toggle.bash"

declare -A keep_awake_setting=(
  [enabled_fn]="idle_audio_enabled"
  [setter_fn]="idle_set_audio"
  [disabled_icon]="audio-speakers-symbolic"
  [enabled_icon]="audio-speakers-symbolic"
  [disabled_summary]="Audio keep awake disabled"
  [enabled_summary]="Audio keep awake enabled"
)
idle_toggle_setting keep_awake_setting
