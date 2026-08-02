#!/usr/bin/env bash
set -euo pipefail

exec python3 "${HOME}/.local/lib/hypr/keybinds/lib/submap_hint.py" "$@"
