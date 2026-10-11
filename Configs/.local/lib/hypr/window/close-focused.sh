#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_help_guard "Usage: hyprshell window/close-focused [--help]

Close the focused Hyprland window." "$@"

hypr_lua_dispatch 'hl.dsp.window.close()' >/dev/null
