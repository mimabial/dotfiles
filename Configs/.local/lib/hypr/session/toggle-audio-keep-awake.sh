#!/usr/bin/env bash

set -euo pipefail

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
