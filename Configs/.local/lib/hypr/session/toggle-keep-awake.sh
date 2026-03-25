#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/idle.state.sh"

idle_toggle_state \
  idle_manual_enabled \
  idle_set_manual \
  0 \
  "caffeine-cup-empty" \
  "Keep awake disabled" \
  1 \
  "caffeine-cup-full" \
  "Keep awake enabled"
