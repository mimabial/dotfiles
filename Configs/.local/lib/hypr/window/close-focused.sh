#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_help_guard "Usage: $(basename "$0") [--help]

Close the Look & Feel panel when it is open; otherwise close the focused
Hyprland window." "$@"

if [[ "$(quickshell ipc call looknfeel isOpen 2>/dev/null || true)" == "true" ]]; then
  exec quickshell ipc call looknfeel close
fi

hypr_lua_dispatch 'hl.dsp.window.close()' >/dev/null
