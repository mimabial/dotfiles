#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require system || exit 1

FONT_NAME="${1:-}"
USER_FONTS_FILE="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/userfonts.lua"

usage() {
  cat <<EOF2
Usage: hyprshell fonts/font-set.sh <font-name>

Sets the shared font override layer for:
  • General UI font
  • Document font
  • Monospace font
  • Bar font
  • Menu font
  • Terminal font
EOF2
  exit 0
}

require_font_name() {
  [[ -n "${FONT_NAME}" && "${FONT_NAME}" != '-h' && "${FONT_NAME}" != '--help' ]] || usage
  if [[ "${FONT_NAME}" == 'CNCLD' ]]; then
    exit 0
  fi
}

require_installed_font() {
  if fc-list | grep -i "${FONT_NAME}" >/dev/null 2>&1; then
    return 0
  fi

  printf "Font '%s' not found in system.\n\n" "${FONT_NAME}" >&2
  printf 'Available monospace fonts:\n' >&2
  hyprshell fonts/font-list.sh | head -20 >&2
  printf '\nInstall fonts from Menu > Install > Font\n' >&2
  exit 1
}

persist_font_selection() {
  local font_lua=""
  font_lua="$(jq -Rn --arg value "${FONT_NAME}" '$value')"
  mkdir -p "$(dirname "${USER_FONTS_FILE}")"
  cat <<LUA >"${USER_FONTS_FILE}"
-- Generated native Hyprland Lua font overrides.
local vars = require("vars")

vars.set("FONT", ${font_lua})
vars.set("DOCUMENT_FONT", ${font_lua})
vars.set("MONOSPACE_FONT", ${font_lua})
vars.set("BAR_FONT", ${font_lua})
vars.set("MENU_FONT", ${font_lua})
vars.set("TERMINAL_FONT", ${font_lua})
LUA
}

require_font_name
require_installed_font
persist_font_selection
hyprshell fonts/font-apply.sh "${FONT_NAME}"
