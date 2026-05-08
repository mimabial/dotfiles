#!/usr/bin/env bash
#
# run-after-close.sh - Close rofi before running a command.
#
# Usage: run-after-close.sh -- <command> [args...]

set -euo pipefail

ROFI_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${ROFI_DIR}/close.bash"

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

rofi_close_running
exec "$@"
