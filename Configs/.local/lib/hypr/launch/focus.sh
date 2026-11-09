#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/lib/window-launch.bash"

usage() {
  cat <<EOF
Usage: hyprshell launch/focus.sh <window-pattern> -- <command> [args...]

Focus a window matching the pattern, or run the command to open one.
EOF
}

main() {
  local window_pattern=""
  local window_address=""
  local launch_cmd=()

  [[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; return; }

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
    source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || return 1
    hypr_lua_dispatch "hl.dsp.focus({window=$(hypr_lua_quote "address:${window_address}")})" >/dev/null 2>&1
    return $?
  fi

  exec "${launch_cmd[@]}"
}

main "$@"
