#!/usr/bin/env bash
set -euo pipefail

exec python3 "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/keybinds/lib/submap_hint.py" "$@"
