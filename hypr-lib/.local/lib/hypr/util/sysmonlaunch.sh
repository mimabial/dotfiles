#!/usr/bin/env bash

echo "SCRIPT STARTED: $(date)" >>/tmp/sysmon-debug.log

scrDir="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${scrDir}/../globalcontrol.sh"

echo "AFTER SOURCE globalcontrol" >>/tmp/sysmon-debug.log

show_help() {
  cat <<HELP
Usage: $(basename "$0") --[option] 
    -h, --help  Display this help and exit
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

case $1 in
  -h | --help)
    show_help
    exit 0
    ;;
  -e | --execute)
    shift
    SYSMONITOR_EXECUTE=$1
    ;;
  -*)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
esac

pidFile="$XDG_RUNTIME_DIR/sysmonlaunch.pid"

echo "PID FILE: $pidFile" >>/tmp/sysmon-debug.log

# TODO: As there is no proper protocol at terminals, we need to find a way to kill the processes
# * This enables toggling the sysmonitor on and off
if [[ -f "${pidFile}" ]]; then
  echo "PID FILE EXISTS - toggling off" >>/tmp/sysmon-debug.log
  while IFS= read -r line; do
    pid=$(awk -F ':::' '{print $1}' <<<"$line")
    if [[ -d "/proc/${pid}" ]]; then
      cmd=$(awk -F ':::' '{print $2}' <<<"$line")
      pkill -P "$pid"
      pkg_installed flatpak && flatpak kill "$cmd" 2>/dev/null
      rm -f "$pidFile"
      echo "KILLED PID $pid" >>/tmp/sysmon-debug.log
      exit 0
    fi
  done <"$pidFile"
  rm -f "$pidFile"
fi

echo "CHECKING MONITORS..." >>/tmp/sysmon-debug.log

pkgChk=("htop" "btop" "top")                                                      # Array of commands to check
pkgChk+=("${SYSMONITOR_COMMANDS[@]}")                                             # Add the user defined array commands
if [[ -n "${SYSMONITOR_EXECUTE}" ]]; then
  pkgChk=("${SYSMONITOR_EXECUTE}" "${pkgChk[@]}")
fi

for sysMon in "${pkgChk[@]}"; do
  if pkg_installed "${sysMon}"; then
    term="${SYSMONITOR_TERMINAL:-${TERMINAL:-kitty}}"
    "${term}" --class=sysmonitor -e "${sysMon}" &
    pid=$!
    echo "${pid}:::${sysMon}" >"$pidFile"
    disown
    break
  fi
done
