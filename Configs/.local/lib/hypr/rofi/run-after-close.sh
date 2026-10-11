#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/close.bash"

usage() {
  cat <<EOF
Usage: $(basename "${0}") -- <command> [args...]
EOF
}

[[ "${1:-}" == "--" ]] && shift
[[ "$#" -gt 0 ]] || {
  usage >&2
  exit 2
}

rofi_ensure_closed || exit 1
exec "$@"
