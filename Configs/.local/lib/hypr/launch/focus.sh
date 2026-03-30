#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/window.common.bash"

usage() {
  echo "Usage: hyprshell launch/focus.sh <window-pattern> -- <command> [args...]"
}

main() {
  local window_pattern=""
  local address=""
  local launch_cmd=()

  if [[ "$#" -lt 3 ]]; then
    usage >&2
    return 1
  fi

  window_pattern="$1"
  shift

  if [[ "$1" != "--" ]]; then
    usage >&2
    return 1
  fi
  shift

  launch_cmd=("$@")
  [[ -n "${window_pattern}" && "${#launch_cmd[@]}" -gt 0 ]] || {
    usage >&2
    return 1
  }

  address="$(launch_resolve_window_address "${window_pattern}")"
  if [[ -n "${address}" ]]; then
    hyprctl dispatch focuswindow "address:${address}" >/dev/null 2>&1
    return $?
  fi

  exec "${launch_cmd[@]}"
}

main "$@"
