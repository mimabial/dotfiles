#!/usr/bin/env bash

set -euo pipefail

windows_usage() {
  echo "Usage: hyprshell vm/windows.sh [command] [options]"
  echo ""
  echo "Commands:"
  echo "  install              Install and configure Windows VM"
  echo "  remove               Remove Windows VM and its data"
  echo "  launch [options]     Start Windows VM (if needed) and connect via RDP"
  echo "                       Options:"
  echo "                         --keep-alive, -k   Keep VM running after RDP closes"
  echo "  stop                 Stop the running Windows VM"
  echo "  status               Show current VM status"
  echo "  help                 Show this help message"
  echo ""
  echo "Examples:"
  echo "  hyprshell vm/windows.sh install           # Set up Windows VM for first time"
  echo "  hyprshell vm/windows.sh launch            # Connect to VM (auto-stop on exit)"
  echo "  hyprshell vm/windows.sh launch -k         # Connect to VM (keep running)"
  echo "  hyprshell vm/windows.sh stop              # Shut down the VM"
}

case "${1:-}" in
  install | remove | launch | start | stop | down | status)
    source "${BASH_SOURCE[0]%/*}/windows/settings.bash"
    source "${BASH_SOURCE[0]%/*}/windows/container.bash"
    ;;
esac

case "${1:-}" in
  install | launch | start)
    # shellcheck source=/dev/null
    source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/notify.bash" || exit 1
    source "${BASH_SOURCE[0]%/*}/windows/compose.bash"
    ;;
esac

case "${1:-}" in
  install)
    source "${BASH_SOURCE[0]%/*}/windows/host.bash"
    source "${BASH_SOURCE[0]%/*}/windows/desktop.bash"
    source "${BASH_SOURCE[0]%/*}/windows/install.bash"
    windows_install
    ;;
  remove) windows_remove ;;
  launch | start)
    source "${BASH_SOURCE[0]%/*}/windows/readiness.bash"
    source "${BASH_SOURCE[0]%/*}/windows/rdp.bash"
    windows_launch "${@:2}"
    ;;
  stop | down) windows_stop ;;
  status) windows_status ;;
  help | --help | -h | "") windows_usage ;;
  *)
    echo "Unknown command: $1" >&2
    echo "" >&2
    windows_usage >&2
    exit 1
    ;;
esac
