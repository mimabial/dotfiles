#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require system || exit 1

FONT_NAME="${1:-}"
USER_FONTS_FILE="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/userfonts.conf"

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

write_font_override() {
  local var_name="$1"
  local value="$2"
  local file_path="$3"
  local replacement="\$${var_name}=${value}"
  local escaped=""

  escaped="$(sed_escape_replacement "${replacement}")"
  mkdir -p "$(dirname "${file_path}")"
  touch "${file_path}"

  if grep -q "^[[:space:]]*\$${var_name}=" "${file_path}"; then
    sed -i "s|^[[:space:]]*\$${var_name}=.*|${escaped}|" "${file_path}"
  else
    printf '\n$%s=%s\n' "${var_name}" "${value}" >>"${file_path}"
  fi
}

persist_font_selection() {
  write_font_override 'FONT' "${FONT_NAME}" "${USER_FONTS_FILE}"
  write_font_override 'DOCUMENT_FONT' "${FONT_NAME}" "${USER_FONTS_FILE}"
  write_font_override 'MONOSPACE_FONT' "${FONT_NAME}" "${USER_FONTS_FILE}"
  write_font_override 'BAR_FONT' "${FONT_NAME}" "${USER_FONTS_FILE}"
  write_font_override 'MENU_FONT' "${FONT_NAME}" "${USER_FONTS_FILE}"
  write_font_override 'TERMINAL_FONT' "${FONT_NAME}" "${USER_FONTS_FILE}"
}

require_font_name
require_installed_font
persist_font_selection
hyprshell fonts/font-apply.sh "${FONT_NAME}"
