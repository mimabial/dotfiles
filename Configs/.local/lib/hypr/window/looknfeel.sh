#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_help_guard "Usage: $(basename "$0") [--help]

Toggle the Look & Feel panel. The panel lives in the running Quickshell
process, so this only sends it an IPC message." "$@"

exec quickshell ipc call looknfeel toggle
