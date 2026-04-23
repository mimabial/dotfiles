#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
font_sync_lib="${LIB_DIR}/hypr/fonts/font.sync.lib.bash"

if [[ ! -r "${font_sync_lib}" ]]; then
  printf 'ERROR: missing %s\n' "${font_sync_lib}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${font_sync_lib}" || exit 1

kind="${1:-}"

usage() {
  cat <<'EOF'
Usage: hyprshell fonts/font-get.sh <kind>

Kinds:
  mono   -> $MONOSPACE_FONT (fallback to native monospace)
  bar    -> $BAR_FONT (fallback to $FONT, then native monospace)
  menu   -> $MENU_FONT (fallback to $FONT, then native monospace)
EOF
}

[[ -z "${kind}" || "${kind}" == "-h" || "${kind}" == "--help" ]] && usage && exit 0

if ! font_sync_resolve_font_value "${kind}"; then
  echo "Unknown kind: ${kind}" >&2
  usage >&2
  exit 2
fi
