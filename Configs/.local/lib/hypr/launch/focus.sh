#!/usr/bin/env bash
#
# focus.sh — Focus an existing window matching a pattern; if none, exec the launch command.
#
# Usage: hyprshell launch/focus.sh <window-pattern> -- <command> [args...]
#
# Depends on: hyprctl, launch/window.common.bash
#
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/window.common.bash"

usage() {
  cat <<EOF
Usage: hyprshell launch/focus.sh <window-pattern> -- <command> [args...]
EOF
}

main() {
  local window_pattern=""
  local window_address=""
  local launch_cmd=()

  if [[ "$#" -lt 3 ]] || [[ "$2" != "--" ]]; then
    usage >&2
    return 2
  fi

  window_pattern="$1"
  shift 2
  launch_cmd=("$@")

  [[ -n "${window_pattern}" && "${#launch_cmd[@]}" -gt 0 ]] || {
    usage >&2
    return 2
  }

  window_address="$(launch_resolve_window_address "${window_pattern}")"
  if [[ -n "${window_address}" ]]; then
    hyprctl dispatch focuswindow "address:${window_address}" >/dev/null 2>&1
    return $?
  fi

  exec "${launch_cmd[@]}"
}

main "$@"
