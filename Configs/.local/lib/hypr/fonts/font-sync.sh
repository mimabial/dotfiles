#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

rofi_to=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rofi-to)
      rofi_to="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: hyprshell fonts/font-sync.sh --rofi-to NEW

Rewrites Rofi font-family strings in *.rasi while keeping existing sizes.
EOF
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if command -v python3 >/dev/null 2>&1; then
  if [[ -n "${rofi_to}" ]]; then
    ROFI_TO="${rofi_to}" python3 "${BASH_SOURCE[0]%/*}/lib/rofi_font_family.py"
  fi
fi
