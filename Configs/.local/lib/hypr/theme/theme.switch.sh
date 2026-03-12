#!/usr/bin/env bash
# shellcheck disable=SC2154
# shellcheck disable=SC1091
#
# theme.switch.sh - Theme switching orchestrator
#
# OVERVIEW:
#   Switches themes, updating all configuration files and
#   triggering color regeneration via color.set.sh.
#
# USAGE:
#   theme.switch.sh -s "Theme Name"   # Switch to specific theme
#   theme.switch.sh -n                # Switch to next theme
#   theme.switch.sh -p                # Switch to previous theme
#
# KEY FUNCTIONS:
#   Theme_Change()         - Navigate to next/previous theme
#   load_hypr_variables()  - Extract variables from theme's hypr.theme
#   sanitize_hypr_theme()  - Remove exec/shadow lines from theme config
#   write_theme_conf()     - Write active theme configuration

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

[ -z "${HYPR_THEME}" ] && echo "ERROR: unable to detect theme" && exit 1
get_themes

# Set default HYPRLAND_CONFIG if not defined
HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr/hyprland.conf}"

# Track and restore Hyprland autoreload setting during theme switch.
hypr_autoreload_prev=""
hypr_autoreload_set=0
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] && command -v hyprctl >/dev/null 2>&1; then
  hypr_autoreload_prev="$(hyprctl getoption misc:disable_autoreload 2>/dev/null | awk -F': ' '/int/ {print $2; exit}')"
  if [[ -n "${hypr_autoreload_prev}" ]]; then
    hyprctl keyword misc:disable_autoreload 1 -q
    hypr_autoreload_set=1
  fi
fi

# Lock file to prevent concurrent theme switching
THEME_SWITCH_LOCK="${XDG_RUNTIME_DIR:-/tmp}/theme-switch.lock"
exec 201>"${THEME_SWITCH_LOCK}"
! flock -n 201 && {
  print_log -sec "theme.switch" -stat "wait" "Another theme operation in progress, waiting..."
  flock 201
}
theme_notify_id=""
theme_notify_supports_p=""
theme_notify_tag="theme-switch"
theme_notify_active=false
theme_notify_app="Theme switch"
theme_notify_icon="preferences-desktop-theme"

theme_switch_source_lib() {
  local lib_file="$1"
  if [[ ! -r "${lib_file}" ]]; then
    print_log -sec "theme" -err "source" "missing ${lib_file}"
    return 1
  fi
  # shellcheck source=/dev/null
  source "${lib_file}"
}

theme_switch_source_lib "${LIB_DIR}/hypr/theme/lib/theme.switch.config.bash" || exit 1
theme_switch_source_lib "${LIB_DIR}/hypr/theme/lib/theme.switch.ui.bash" || exit 1
theme_switch_source_lib "${LIB_DIR}/hypr/theme/lib/theme.switch.wallpaper.bash" || exit 1

cleanup_theme_switch() {
  local exit_code=$?
  theme_notify_finish "${exit_code}"
  if [[ "${hypr_autoreload_set}" -eq 1 ]] && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl keyword misc:disable_autoreload "${hypr_autoreload_prev}" -q
  fi
  flock -u 201 2>/dev/null
}
trap 'cleanup_theme_switch' EXIT

#// evaluate options
quiet=false
while getopts "qnps:" option; do
  case $option in

    n) # set next theme
      Theme_Change n
      export xtrans="grow"
      ;;

    p) # set previous theme
      Theme_Change p
      export xtrans="outer"
      ;;

    s) # set selected theme
      themeSet="$OPTARG" ;;
    q)
      quiet=true
      ;;
    *) # invalid option
      echo "... invalid option ..."
      echo "$(basename "${0}") -[option]"
      echo "n : set next theme"
      echo "p : set previous theme"
      echo "s : set input theme"
      exit 1
      ;;
  esac
done

#// update control file

# shellcheck disable=SC2076
[[ ! " ${thmList[*]} " =~ " ${themeSet} " ]] && themeSet="${HYPR_THEME}"

state_set "HYPR_THEME" "${themeSet}" "staterc"
print_log -sec "theme" -stat "apply" "${themeSet}"
theme_notify_start

export reload_flag=1
source "${LIB_DIR}/hypr/globalcontrol.sh"
[[ -f "${HYPR_CONFIG_HOME}/env-theme" ]] && source "${HYPR_CONFIG_HOME}/env-theme"

#// hypr
if [[ -r "${HYPRLAND_CONFIG}" ]]; then

  # shellcheck disable=SC2154
  # Updates the compositor theme data in advance
  [[ -r "${HYPR_THEME_DIR}/hypr.theme" ]] && sanitize_hypr_theme "${HYPR_THEME_DIR}/hypr.theme" "${XDG_CONFIG_HOME}/hypr/themes/theme.conf"

  #? Load theme specific variables
  load_hypr_variables "${HYPR_THEME_DIR}/hypr.theme"

  #? Load User's hyprland overrides
  load_hypr_variables "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/hyprland.conf"

fi

show_theme_status

# Apply cursor immediately so UI feedback isn't delayed by long theming tasks.
if [[ -n "${CURSOR_THEME}" ]] && [[ -n "${CURSOR_SIZE}" ]]; then
  hyprctl setcursor "${CURSOR_THEME}" "${CURSOR_SIZE}" >/dev/null 2>&1 &
fi

# Early load the icon theme so that it is available for the rest of the script
if ! dconf write /org/gnome/desktop/interface/icon-theme "'${ICON_THEME}'"; then
  print_log -sec "theme" -warn "dconf" "failed to set icon theme"
fi

# Resolve theme directories for local and NixOS installs.
if [ -d /run/current-system/sw/share/themes ]; then
  export THEMES_DIR=/run/current-system/sw/share/themes
fi

if [ ! -d "${THEMES_DIR}/${GTK_THEME}" ] && [ -d "$HOME/.themes/${GTK_THEME}" ]; then
  cp -rns "$HOME/.themes/${GTK_THEME}" "${THEMES_DIR}/${GTK_THEME}"
fi

# Font fallbacks (avoid empty qt5ct/qt6ct font strings)
[[ -z "${FONT}" ]] && FONT="Canterell"
[[ -z "${MONOSPACE_FONT}" ]] && MONOSPACE_FONT="CaskaydiaCove Nerd Font Mono"

#// qt5ct + qt6ct (batched)

QT5_FONT="${QT5_FONT:-${FONT}}"
QT5_FONT_SIZE="${QT5_FONT_SIZE:-${FONT_SIZE}}"
QT5_MONOSPACE_FONT="${QT5_MONOSPACE_FONT:-${MONOSPACE_FONT}}"
QT5_MONOSPACE_FONT_SIZE="${QT5_MONOSPACE_FONT_SIZE:-${MONOSPACE_FONT_SIZE:-9}}"
QT6_FONT="${QT6_FONT:-${FONT}}"
QT6_FONT_SIZE="${QT6_FONT_SIZE:-${FONT_SIZE}}"
QT6_MONOSPACE_FONT="${QT6_MONOSPACE_FONT:-${MONOSPACE_FONT}}"
QT6_MONOSPACE_FONT_SIZE="${QT6_MONOSPACE_FONT_SIZE:-${MONOSPACE_FONT_SIZE:-9}}"

ini_write_batch "${XDG_CONFIG_HOME}/qt5ct/qt5ct.conf" \
  "Appearance:icon_theme=${ICON_THEME}" \
  "Fonts:general=\"${QT5_FONT},${QT5_FONT_SIZE},-1,5,50,0,0,0,0,0,${QT_FONT_STYLE}\"" \
  "Fonts:fixed=\"${QT5_MONOSPACE_FONT},${QT5_MONOSPACE_FONT_SIZE},-1,5,50,0,0,0,0,0\""

ini_write_batch "${XDG_CONFIG_HOME}/qt6ct/qt6ct.conf" \
  "Appearance:icon_theme=${ICON_THEME}" \
  "Fonts:general=\"${QT6_FONT},${QT6_FONT_SIZE},-1,5,400,0,0,0,0,0,0,0,0,0,0,1,${QT_FONT_STYLE}\"" \
  "Fonts:fixed=\"${QT6_MONOSPACE_FONT},${QT6_MONOSPACE_FONT_SIZE:-9},-1,5,400,0,0,0,0,0,0,0,0,0,0,1\""

# // kde plasma (batched)

if [[ -z "${TERMINAL}" ]]; then
  _hypr_variables_file="$(hypr_variables_file 2>/dev/null || printf '%s\n' "${HYPR_DATA_HOME}/variables.conf")"
  TERMINAL="$(get_hyprConf "TERMINAL" "${_hypr_variables_file}")"
fi

kdeglobals_entries=(
  "Icons:Theme=${ICON_THEME}"
  "KDE:widgetStyle=kvantum"
)

# Only set UiSettings/ColorScheme when the scheme file exists.
# Some Qt/Kirigami apps (e.g. Haruna) will drop invalid scheme names and may
# show fallback colors on first launch.
KDE_COLOR_SCHEME="${KDE_COLOR_SCHEME:-colors}"
KDE_COLOR_SCHEME_FILE=""
for _scheme_dir in "${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes" "/usr/share/color-schemes"; do
  if [[ -f "${_scheme_dir}/${KDE_COLOR_SCHEME}.colors" ]]; then
    KDE_COLOR_SCHEME_FILE="${_scheme_dir}/${KDE_COLOR_SCHEME}.colors"
    break
  fi
done
if [[ -n "${KDE_COLOR_SCHEME_FILE}" ]]; then
  kdeglobals_entries+=("UiSettings:ColorScheme=${KDE_COLOR_SCHEME}")
else
  if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file "${XDG_CONFIG_HOME}/kdeglobals" --group "UiSettings" --key "ColorScheme" --delete >/dev/null 2>&1 || true
  fi
  print_log -sec "theme" -warn "kdeglobals" "ColorScheme '${KDE_COLOR_SCHEME}' not found; leaving UiSettings unset"
fi
if [[ -n "${TERMINAL}" ]]; then
  kdeglobals_entries+=("General:TerminalApplication=${TERMINAL}")
else
  print_log -sec "theme" -warn "terminal" "TerminalApplication is empty; leaving kdeglobals value unchanged"
fi

ini_write_batch "${XDG_CONFIG_HOME}/kdeglobals" "${kdeglobals_entries[@]}"

# // The default cursor theme // fallback

ini_write_batch "${XDG_DATA_HOME}/icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}"
ini_write_batch "${HOME}/.icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}"

# // gtk2

sed -i -e "/^gtk-theme-name=/c\gtk-theme-name=\"${GTK_THEME}\"" \
  -e "/^include /c\include \"$HOME/.gtkrc-2.0.mime\"" \
  -e "/^gtk-cursor-theme-name=/c\gtk-cursor-theme-name=\"${CURSOR_THEME}\"" \
  -e "/^gtk-icon-theme-name=/c\gtk-icon-theme-name=\"${ICON_THEME}\"" "$HOME/.gtkrc-2.0"

#// gtk3 (batched)

GTK3_FONT="${GTK3_FONT:-${FONT}}"
GTK3_FONT_SIZE="${GTK3_FONT_SIZE:-${FONT_SIZE}}"

ini_write_batch "${XDG_CONFIG_HOME}/gtk-3.0/settings.ini" \
  "Settings:gtk-theme-name=${GTK_THEME}" \
  "Settings:gtk-icon-theme-name=${ICON_THEME}" \
  "Settings:gtk-cursor-theme-name=${CURSOR_THEME}" \
  "Settings:gtk-cursor-theme-size=${CURSOR_SIZE}" \
  "Settings:gtk-font-name=${GTK3_FONT} ${GTK3_FONT_SIZE}"

#// gtk4
if [ -d "${THEMES_DIR}/${GTK_THEME}/gtk-4.0" ]; then
  gtk4Theme="${GTK_THEME}"
else
  gtk4Theme="Pywal16-Gtk"
  print_log -sec "theme" -stat "use" "'Pywal16-Gtk' as gtk4 theme"
fi
rm -rf "${XDG_CONFIG_HOME}/gtk-4.0"
if [ -d "${THEMES_DIR}/${gtk4Theme}/gtk-4.0" ]; then
  ln -s "${THEMES_DIR}/${gtk4Theme}/gtk-4.0" "${XDG_CONFIG_HOME}/gtk-4.0"
else
  print_log -sec "theme" -warn "gtk4" "theme directory '${THEMES_DIR}/${gtk4Theme}/gtk-4.0' does not exist"
fi

#// flatpak GTK

if pkg_installed flatpak; then
  flatpak \
    --user override \
    --filesystem="${THEMES_DIR}" \
    --filesystem="$HOME/.themes" \
    --filesystem="$HOME/.icons" \
    --filesystem="$HOME/.local/share/icons" \
    --env=GTK_THEME="${gtk4Theme}" \
    --env=ICON_THEME="${ICON_THEME}"

  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &

fi
# // xsettingsd

sed -i -e "/^Net\/ThemeName /c\Net\/ThemeName \"${GTK_THEME}\"" \
  -e "/^Net\/IconThemeName /c\Net\/IconThemeName \"${ICON_THEME}\"" \
  -e "/^Gtk\/CursorThemeName /c\Gtk\/CursorThemeName \"${CURSOR_THEME}\"" \
  -e "/^Gtk\/CursorThemeSize /c\Gtk\/CursorThemeSize ${CURSOR_SIZE}" \
  "${XDG_CONFIG_HOME}/xsettingsd/xsettingsd.conf"

# // Legacy themes using ~/.themes also fixed GTK4 not following xdg

if [ ! -L "$HOME/.themes/${GTK_THEME}" ] && [ -d "${THEMES_DIR}/${GTK_THEME}" ]; then
  print_log -sec "theme" -warn "linking" "${GTK_THEME} to ~/.themes to fix GTK4 not following xdg"
  mkdir -p "$HOME/.themes"
  rm -rf "$HOME/.themes/${GTK_THEME}"
  ln -snf "${THEMES_DIR}/${GTK_THEME}" "$HOME/.themes/"
fi

# // .Xresources
if [ -f "$HOME/.Xresources" ]; then
  sed -i -e "/^Xcursor\.theme:/c\Xcursor.theme: ${CURSOR_THEME}" \
    -e "/^Xcursor\.size:/c\Xcursor.size: ${CURSOR_SIZE}" "$HOME/.Xresources"

  # Add if they don't exist
  grep -q "^Xcursor\.theme:" "$HOME/.Xresources" || echo "Xcursor.theme: ${CURSOR_THEME}" >>"$HOME/.Xresources"
  grep -q "^Xcursor\.size:" "$HOME/.Xresources" || echo "Xcursor.size: 30" >>"$HOME/.Xresources"
else
  # Create .Xresources if it doesn't exist
  cat >"$HOME/.Xresources" <<EOF
Xcursor.theme: ${CURSOR_THEME}
Xcursor.size: ${CURSOR_SIZE}
EOF
fi

# // .Xdefaults

if [ -f "$HOME/.Xdefaults" ]; then
  sed -i -e "/^Xcursor\.theme:/c\Xcursor.theme: ${CURSOR_THEME}" \
    -e "/^Xcursor\.size:/c\Xcursor.size: ${CURSOR_SIZE}" "$HOME/.Xdefaults"

  # Add if they don't exist
  grep -q "^Xcursor\.theme:" "$HOME/.Xdefaults" || echo "Xcursor.theme: ${CURSOR_THEME}" >>"$HOME/.Xdefaults"
  grep -q "^Xcursor\.size:" "$HOME/.Xdefaults" || echo "Xcursor.size: 30" >>"$HOME/.Xdefaults"
fi

#? Workaround for gtk-4 having settings.ini!
if [ -f "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini" ]; then
  rm "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini"
fi

#// wallpaper
export -f pkg_installed

[[ -d "$WALLPAPER_CURRENT_DIR" ]] && find -H "$WALLPAPER_CURRENT_DIR" -name "*.png" -exec sh -c '
    for file; do
        base=$(basename "$file" .png)
        if pkg_installed "${base}"; then
            "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" --link --backend "${base}"
        fi
    done
' sh {} + &

wallpaper_target="${HYPR_THEME_DIR}/wall.set"
wallpaper_path="$(
  readlink -f -- "${wallpaper_target}" 2>/dev/null \
    || realpath -- "${wallpaper_target}" 2>/dev/null \
    || printf '%s' "${wallpaper_target}"
)"
if [ "$quiet" = true ]; then
  "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" -s "${wallpaper_path}" --global >/dev/null 2>&1
else
  "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" -s "${wallpaper_path}" --global
fi

# Theme mode: apply theme palette and .theme files (wallpaper sets no colors here)
if [[ "${enableWallDcol}" -eq 0 ]]; then
  "${LIB_DIR}/hypr/theme/color.set.sh"
fi

#// nvim sync (after wallpaper/colors so pywal theme reads correct colors)
if [[ -x "${scrDir}/util/nvim-theme-sync.sh" ]]; then
  "${scrDir}/util/nvim-theme-sync.sh" >/dev/null 2>&1 || true
fi

theme_thumbs_precache
