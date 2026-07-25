#!/usr/bin/env bash
set -euo pipefail

source "$(command -v hyprshell)" || exit 1

exec python3 "${HYPR_LIB_DIR}/keybinds/lib/submap_hint.py" "$@"
