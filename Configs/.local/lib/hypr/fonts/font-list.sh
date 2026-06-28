#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell fonts/font-list
List installed font families, excluding monospace and emoji fonts." "$@"

fc-list :spacing=100 -f "%{family[0]}\n" \
  | awk 'tolower($0) !~ /(^|[^[:alnum:]])(emoji|signwriting)([^[:alnum:]]|$)/' \
  | awk '$0 !~ /(^| )Mono($| )/' \
  | sort -u
