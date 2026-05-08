#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Shared helpers for control scripts (volume/brightness/network/audio switch).

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1
}

is_true() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}
