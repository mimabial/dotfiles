#!/usr/bin/env bash
set -euo pipefail
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell quickshell/visibility [toggle|hide|show|reveal]
Drive the bar's own visibility over its IPC socket (default: toggle).
  reveal   show it until the pointer leaves, without clearing the hidden flag" "$@"

action="${1:-toggle}"
case "${action}" in
  toggle | hide | show | reveal) ;;
  *) printf 'unknown action: %s\n' "${action}" >&2; exit 1 ;;
esac

command -v quickshell >/dev/null 2>&1 || { printf 'quickshell is not installed\n' >&2; exit 1; }
# --any-display: the bind can fire from a monitor the socket is not tied to
exec quickshell ipc --any-display call bar "${action}"
