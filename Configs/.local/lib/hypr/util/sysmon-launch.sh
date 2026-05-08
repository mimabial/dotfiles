#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh"

show_help() {
  cat <<HELP
Usage: $(basename "$0") --[option]
    -h, --help      Display this help and exit
    -e, --execute   Explicit command to execute

Config: ~/.config/hypr/config.toml

    [sysmonitor]
    execute = "btop"                    # Default command to execute // accepts executable or app.desktop
    commands = ["btop", "htop", "top"]  # Fallback command options
    terminal = "kitty"                  # Explicit terminal // uses \$TERMINAL if available

This script launches the system monitor application.
    It will launch the first available system monitor
    application from the list of 'commands' provided.
HELP
}

toggle_existing_monitor() {
  local address=""

  address="$(
    hyprctl -j clients 2>/dev/null \
      | jq -r '.[] | select(.class == "org.tui.Sysmonitor") | .address' \
      | head -n1
  )"
  [[ -n "${address}" ]] || return 1

  hyprctl dispatch closewindow "address:${address}" >/dev/null 2>&1
}

select_monitor_command() {
  local -a pkgChk=("htop" "btop" "top")
  local sysMon=""

  pkgChk+=("${SYSMONITOR_COMMANDS[@]}")
  if [[ -n "${SYSMONITOR_EXECUTE}" ]]; then
    pkgChk=("${SYSMONITOR_EXECUTE}" "${pkgChk[@]}")
  fi

  for sysMon in "${pkgChk[@]}"; do
    [[ -n "${sysMon}" ]] || continue
    if pkg_installed "${sysMon}"; then
      printf '%s\n' "${sysMon}"
      return 0
    fi
  done

  return 1
}

launch_monitor() {
  local sysMon="$1"
  local term="${SYSMONITOR_TERMINAL:-${TERMINAL_TUI:-${TERMINAL:-kitty}}}"

  TERMINAL_TUI="${term}" \
    exec "${LIB_DIR:-$HOME/.local/lib}/hypr/launch/tui.sh" \
      --app-id org.tui.Sysmonitor \
      --title "System Monitor" \
      -- "${sysMon}"
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

sysMon="$(select_monitor_command)" || exit 1
launch_monitor "${sysMon}"
