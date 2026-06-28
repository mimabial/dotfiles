#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/powerprofiles
List the available power profiles (active first)." "$@"

powerprofilesctl list |
  awk '/^\s*[* ]\s*[a-zA-Z0-9\-]+:$/ { gsub(/^[*[:space:]]+|:$/,""); print }' |
  tac
