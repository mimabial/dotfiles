#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system || exit 1
hypr_runtime_load_state || exit 1

show_help() {
  cat <<HELP
Usage: $(basename "$0") --[option]
    -h, --help      Display this help and exit
    -e, --execute   Explicit command to execute, arguments included ("dua i")

Overrides: ${XDG_STATE_HOME}/hypr/env-overrides
    SYSMONITOR_EXECUTE="htop"
    SYSMONITOR_COMMANDS=("nvtop")  # Extra fallbacks
    SYSMONITOR_TERMINAL="foot"

This script launches the system monitor application.
    It will launch the first available system monitor
    application from the list of 'commands' provided.
HELP
}

toggle_existing_monitor() {
  local address=""

  address="$(
    hyprctl -j clients 2>/dev/null \
      | jq -r 'first(.[] | select(.class == "org.tui.Sysmonitor") | .address) // empty'
  )"
  [[ -n "${address}" ]] || return 1

  hypr_lua_dispatch "hl.dsp.window.close({window=$(hypr_lua_quote "address:${address}")})" >/dev/null 2>&1
}

select_monitor_command() {
  local -a monitor_candidates=("htop" "btop" "top")
  local candidate=""

  [[ -n "${SYSMONITOR_COMMANDS+set}" ]] && monitor_candidates+=("${SYSMONITOR_COMMANDS[@]}")
  if [[ -n "${SYSMONITOR_EXECUTE:-}" ]]; then
    monitor_candidates=("${SYSMONITOR_EXECUTE}" "${monitor_candidates[@]}")
  fi

  for candidate in "${monitor_candidates[@]}"; do
    [[ -n "${candidate}" ]] || continue
    if pkg_installed "${candidate%% *}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

launch_monitor() {
  local -a monitor_argv=()
  read -ra monitor_argv <<<"$1"
  local terminal_command="${SYSMONITOR_TERMINAL:-${TERMINAL_TUI:-${TERMINAL:-foot}}}"

  TERMINAL_TUI="${terminal_command}" \
    exec "${LIB_DIR:-$HOME/.local/lib}/hypr/launch/tui.sh" \
      --app-id org.tui.Sysmonitor \
      --title "System Monitor" \
      -- "${monitor_argv[@]}"
}

case "${1:-}" in
  -h | --help)
    show_help
    exit 0
    ;;
  -e | --execute)
    shift
    [[ -n "${1:-}" ]] || {
      echo "Missing argument for --execute" >&2
      exit 1
    }
    SYSMONITOR_EXECUTE=$1
    ;;
  --execute=*)
    SYSMONITOR_EXECUTE="${1#--execute=}"
    [[ -n "${SYSMONITOR_EXECUTE}" ]] || {
      echo "Missing argument for --execute" >&2
      exit 1
    }
    ;;
  -* )
    echo "Unknown option: $1" >&2
    exit 1
    ;;
esac

toggle_existing_monitor && exit 0

monitor_command="$(select_monitor_command)" || exit 1
launch_monitor "${monitor_command}"
