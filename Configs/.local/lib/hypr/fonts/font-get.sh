#!/usr/bin/env bash

set -euo pipefail

if ! declare -F hypr_config_value_from_layers >/dev/null 2>&1; then
  LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
fi

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

general_font="$(hypr_config_value_from_layers "FONT" || true)"
mono_font="$(hypr_config_value_from_layers "MONOSPACE_FONT" || true)"
bar_font="$(hypr_config_value_from_layers "BAR_FONT" || true)"
menu_font="$(hypr_config_value_from_layers "MENU_FONT" || true)"

mono_font="${mono_font:-monospace}"
bar_font="${bar_font:-${general_font:-monospace}}"
menu_font="${menu_font:-${general_font:-monospace}}"

case "${kind}" in
  mono) echo "${mono_font}" ;;
  bar) echo "${bar_font}" ;;
  menu) echo "${menu_font}" ;;
  *)
    echo "Unknown kind: ${kind}" >&2
    usage >&2
    exit 2
    ;;
esac
