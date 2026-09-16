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

source "${LIB_DIR}/hypr/core/state.sh"
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

(
  HOME="${tmp_dir}/home" STATE_DIR="${HYPR_STATE_HOME}" HYPR_THEME='New Pack'
  mkdir -p "${HOME}/.themes" "${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}/gtk-3.0" "${HYPR_CONFIG_HOME}/themes/Old/gtk-3.0"
  ln -s "${HYPR_CONFIG_HOME}/themes/Gone" "${HOME}/.themes/Gone"
  ln -s "${HYPR_CONFIG_HOME}/themes/Old" "${HOME}/.themes/Old"
  ln -s "${tmp_dir}/foreign" "${HOME}/.themes/Foreign"
  theme_desktop_resolve_values
  links=("${HOME}/.themes"/*)
  check "${RESOLVED_GTK_THEME}:${links[*]##*/}" 'New-Pack:Foreign New-Pack' gtk-theme-link-prune
)

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

FONT='Test Sans'
MONOSPACE_FONT='Test Mono'
ICON_THEME='Test Icons'
RESOLVED_KDE_COLOR_SCHEME='KvGnome'
RESOLVED_KDE_WIDGET_STYLE='Breeze'
RESOLVED_KVANTUM_THEME='test-kvantum'
theme_desktop_configure_qt_kde_bridge
ui_scheme="$(awk '/^\[UiSettings\]$/ { found=1; next } /^\[/ { found=0 } found && /^ColorScheme=/ { print; exit }' "${XDG_CONFIG_HOME}/kdeglobals")"
check "${ui_scheme}" 'ColorScheme=' system-kde-scheme
kde_style="$(awk '/^\[KDE\]$/ { found=1; next } /^\[/ { found=0 } found && /^widgetStyle=/ { print; exit }' "${XDG_CONFIG_HOME}/kdeglobals")"
check "${kde_style}" 'widgetStyle=Breeze' live-kde-style
qt_style="$(awk '/^\[Appearance\]$/ { found=1; next } /^\[/ { found=0 } found && /^style=/ { print; exit }' "${XDG_CONFIG_HOME}/qt6ct/qt6ct.conf")"
check "${qt_style}" 'style=Breeze' qtct-style

notifications=()
# shellcheck disable=SC2329
dbus-send() { notifications+=("$*"); }
theme_desktop_notify_kde_palette_changed
theme_desktop_notify_kde_icons_changed
check "${#notifications[@]}" 7 kde-notification-count
check "${notifications[0]}" '--session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0' kde-palette-notification
for group in {0..5}; do
  check "${notifications[$((group + 1))]}" "--session --type=signal /KIconLoader org.kde.KIconLoader.iconChanged int32:${group}" "kde-icon-notification-${group}"
done
unset -f dbus-send

(
  HOME="${tmp_dir}/home" STATE_DIR="${HYPR_STATE_HOME}" HYPR_THEME=''
  mkdir -p "${XDG_DATA_HOME}/themes/Pywal16-Gtk/gtk-3.0"
  touch "${XDG_DATA_HOME}/themes/Pywal16-Gtk/gtk-3.0/gtk.css"
  printf '%s\n' 'Pywal16-Gtk-Alt' >"${XDG_DATA_HOME}/themes/Pywal16-Gtk/theme-name"
  theme_desktop_resolve_values
  check "${RESOLVED_GTK_THEME}" 'Pywal16-Gtk-Alt' generated-gtk-theme-name
)

gtk_notifications=()
# shellcheck disable=SC2329
gsettings() { gtk_notifications+=("gsettings $*"); }
# shellcheck disable=SC2329
pkill() { gtk_notifications+=("pkill $*"); }
theme_desktop_notify_gtk_theme_changed
check "${gtk_notifications[*]}" 'pkill -HUP -x xsettingsd' xsettings-reload-only
unset -f gsettings pkill

marker="${tmp_dir}/continued"
theme_desktop_install_kvantum_theme() { return 1; }
theme_desktop_install_kde_color_scheme() { touch "${marker}"; }
if theme_desktop_apply_static_resolved; then
  printf 'failed: static error was masked\n' >&2
  exit 1
fi
[[ ! -e "${marker}" ]]
