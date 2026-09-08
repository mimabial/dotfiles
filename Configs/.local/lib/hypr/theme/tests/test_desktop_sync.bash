#!/usr/bin/env bash
set -euo pipefail

THEME_DIR="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)"
LIB_DIR="${THEME_DIR%/hypr/theme}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT
export XDG_CONFIG_HOME="${tmp_dir}/config" XDG_DATA_HOME="${tmp_dir}/data"
export XDG_CACHE_HOME="${tmp_dir}/cache" HYPR_CONFIG_HOME="${XDG_CONFIG_HOME}/hypr"
export HYPR_CACHE_HOME="${XDG_CACHE_HOME}/hypr" HYPR_STATE_HOME="${tmp_dir}/state"
mkdir -p "${HYPR_CONFIG_HOME}/themes" "${XDG_DATA_HOME}/hypr"

source "${LIB_DIR}/hypr/core/common.sh"
source "${LIB_DIR}/hypr/core/system.sh"
hypr_hash_cache_runtime_file() { :; }
source "${THEME_DIR}/lib/desktop.sync.bash"
check() { [[ "$1" == "$2" ]] || { printf 'failed: %s\n' "$3" >&2; exit 1; }; }

printf '%s\n' "FONT='Env Font'" "ICON_THEME='Env Icons'" >"${HYPR_CONFIG_HOME}/env-theme"
printf '%s\n' 'vars.set("FONT", "User Font")' 'vars.set("MONOSPACE_FONT", "User Mono")' >"${HYPR_CONFIG_HOME}/userfonts.lua"
printf '%s\n' '$FONT=Theme Font' '$ICON_THEME=Theme Icons' '$CURSOR_THEME=Theme Cursor' '$CURSOR_SIZE=28' >"${HYPR_CONFIG_HOME}/themes/theme.meta"
printf '%s\n' '$FONT=Default Font' '$FONT_SIZE=11' '$DOCUMENT_FONT=Default Doc' '$MONOSPACE_FONT=Default Mono' >"${XDG_DATA_HOME}/hypr/variables.meta"

selected_color_source=theme
theme_desktop_resolve_base_values
check "${FONT}" 'Env Font' env-precedence
check "${MONOSPACE_FONT}" 'User Mono' user-precedence
check "${DOCUMENT_FONT}" 'Default Doc' default-layer
check "${ICON_THEME}:${CURSOR_THEME}:${CURSOR_SIZE}" 'Theme Icons:Theme Cursor:28' theme-assets
selected_color_source=wallpaper
theme_desktop_resolve_base_values
check "${ICON_THEME}" 'Env Icons' wallpaper-precedence

ini_file="${tmp_dir}/settings.ini"
printf '%s\n' '[General]' 'Keep=yes' 'Color=old' >"${ini_file}"
theme_desktop_ini_write_batch "${ini_file}" 'General:Color=new' 'Icons:Theme=Tela'
grep -qx 'Keep=yes' "${ini_file}"
grep -qx 'Color=new' "${ini_file}"
grep -qx 'Theme=Tela' "${ini_file}"

generated="${tmp_dir}/generated/file"
printf same | theme_desktop_write_generated_file "${generated}"
inode="$(stat -c %i "${generated}")"
printf same | theme_desktop_write_generated_file "${generated}"
check "$(stat -c %i "${generated}")" "${inode}" unchanged-generated-file

CURSOR_THEME='Test Cursor'
CURSOR_SIZE=32
resource="${tmp_dir}/Xresources"
printf '%s\n' 'keep: yes' 'Xcursor.theme: old' 'Xcursor.theme: duplicate' >"${resource}"
theme_desktop_update_xcursor_resource "${resource}"
check "$(grep -c '^Xcursor.theme:' "${resource}")" 1 cursor-dedup
grep -qx 'Xcursor.theme: Test Cursor' "${resource}"
grep -qx 'Xcursor.size: 32' "${resource}"
grep -qx 'keep: yes' "${resource}"

marker="${tmp_dir}/continued"
theme_desktop_install_kvantum_theme() { return 1; }
theme_desktop_install_kde_color_scheme() { touch "${marker}"; }
if theme_desktop_apply_static_resolved; then
  printf 'failed: static error was masked\n' >&2
  exit 1
fi
[[ ! -e "${marker}" ]]
