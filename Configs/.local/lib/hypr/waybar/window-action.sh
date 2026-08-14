#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.sh"
[[ -n "${1:-}" ]] || exit 2
window="$(hypr_lua_quote "address:$1")"
case "${2:-}" in
  1) action="hl.dsp.focus({window=${window}})" ;;
  2) action="hl.dsp.window.close({window=${window}})" ;;
  3) action="hl.dsp.window.fullscreen({mode=\"fullscreen\",action=\"toggle\",window=${window}})" ;;
  *) exit 0 ;;
esac
hypr_lua_dispatch "${action}" >/dev/null
