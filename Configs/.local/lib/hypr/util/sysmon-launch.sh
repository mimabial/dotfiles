#!/usr/bin/env bash

# shellcheck disable=SC1091
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

stop_process_tree() {
  local pid="$1"
  local pgid="$2"
  local cmd="$3"
  local stopped=false

  if [[ "${pgid}" =~ ^[0-9]+$ ]] && kill -0 -- "-${pgid}" 2>/dev/null; then
    kill -TERM -- "-${pgid}" 2>/dev/null || true
    for _ in {1..10}; do
      kill -0 -- "-${pgid}" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 -- "-${pgid}" 2>/dev/null; then
      kill -KILL -- "-${pgid}" 2>/dev/null || true
    fi
    stopped=true
  elif [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
    kill -TERM "${pid}" 2>/dev/null || true
    for _ in {1..10}; do
      kill -0 "${pid}" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "${pid}" 2>/dev/null; then
      kill -KILL "${pid}" 2>/dev/null || true
    fi
    stopped=true
  fi

  if pkg_installed flatpak && [[ -n "${cmd}" ]]; then
    flatpak kill "${cmd}" 2>/dev/null || true
  fi

  [[ "${stopped}" == true ]]
}

toggle_existing_monitor() {
  local pid=""
  local pgid=""
  local cmd=""

  [[ -f "${pidFile}" ]] || return 1

  while IFS= read -r line; do
    pid=$(awk -F ':::' '{print $1}' <<<"${line}")
    pgid=$(awk -F ':::' '{print $2}' <<<"${line}")
    cmd=$(awk -F ':::' '{print $3}' <<<"${line}")

    if stop_process_tree "${pid}" "${pgid}" "${cmd}"; then
      rm -f "${pidFile}"
      return 0
    fi
  done <"${pidFile}"

  rm -f "${pidFile}"
  return 1
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
  local term="${SYSMONITOR_TERMINAL:-${TERMINAL:-kitty}}"
  local pid=""
  local pgid=""

  setsid "${term}" --class=sysmonitor -e "${sysMon}" >/dev/null 2>&1 &
  pid=$!
  disown

  sleep 0.1
  pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ')"
  [[ "${pgid}" =~ ^[0-9]+$ ]] || pgid="${pid}"

  printf '%s:::%s:::%s\n' "${pid}" "${pgid}" "${sysMon}" >"${pidFile}"
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

pidFile="${XDG_RUNTIME_DIR:-/tmp}/sysmon-launch.pid"
mkdir -p "$(dirname "${pidFile}")"

toggle_existing_monitor && exit 0

sysMon="$(select_monitor_command)" || exit 1
launch_monitor "${sysMon}"
