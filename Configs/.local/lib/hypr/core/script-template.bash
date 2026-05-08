#!/usr/bin/env bash
#
# <name>.sh — <one-line purpose>
#
# Usage:
#   <name>.sh [-flag] <arg>
#
# Depends on: <runtime modules + external commands>
#
set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state notify || exit 1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -h, --help    Show this help
EOF
}

main() {
  local arg=""

  while (( $# )); do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
      *)
        arg="$1"
        shift
        ;;
    esac
    shift || true
  done

  [[ -n "${arg}" ]] || {
    usage >&2
    return 2
  }

  print_log -sec "<section>" -stat "run" "${arg}"
}

main "$@"
