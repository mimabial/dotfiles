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
#   select_adjacent_theme() - Navigate to next/previous theme
#   load_hypr_variables()  - Extract variables from theme's hypr.theme
#   sanitize_hypr_theme()  - Remove exec/shadow lines from theme config
#   write_theme_conf()     - Write active theme configuration

source "$(command -v hyprshell)" || exit 1

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
THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"

exec 201>"${THEME_SWITCH_LOCK}"
! flock -n 201 && {
  print_log -sec "theme.switch" -stat "drop" "Another theme operation is already in progress"
  exit 0
}

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
      select_adjacent_theme n
      ;;

    p) # set previous theme
      select_adjacent_theme p
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
declare -F export_hypr_config >/dev/null 2>&1 && export_hypr_config
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
if [[ -n "${CURSOR_THEME}" ]] && [[ -n "${CURSOR_SIZE}" ]] && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  if ! hyprctl setcursor "${CURSOR_THEME}" "${CURSOR_SIZE}" >/dev/null 2>&1; then
    print_log -sec "theme" -warn "cursor" "failed to apply ${CURSOR_THEME} (${CURSOR_SIZE})"
  fi
fi

# Early load the icon theme so that it is available for the rest of the script
if ! dconf write /org/gnome/desktop/interface/icon-theme "'${ICON_THEME}'"; then
  print_log -sec "theme" -warn "dconf" "failed to set icon theme"
fi

# Resolve theme directories for local and NixOS installs.
if [ -d /run/current-system/sw/share/themes ]; then
  export THEMES_DIR=/run/current-system/sw/share/themes
fi

is_safe_path_component() {
  local value="$1"
  [[ -n "${value}" ]] &&
    [[ "${value}" != "." ]] &&
    [[ "${value}" != ".." ]] &&
    [[ "${value}" != */* ]] &&
    [[ "${value}" != *$'\n'* ]] &&
    [[ "${value}" != *$'\r'* ]]
}

gtk_theme_path_name=""
if is_safe_path_component "${GTK_THEME}"; then
  gtk_theme_path_name="${GTK_THEME}"
else
  print_log -sec "theme" -warn "gtk" "unsafe theme path component: ${GTK_THEME}"
fi

if [[ -n "${gtk_theme_path_name}" ]] && [ ! -d "${THEMES_DIR}/${gtk_theme_path_name}" ] && [ -d "$HOME/.themes/${gtk_theme_path_name}" ]; then
  cp -rns "$HOME/.themes/${gtk_theme_path_name}" "${THEMES_DIR}/${gtk_theme_path_name}"
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
  TERMINAL="$(get_hypr_conf "TERMINAL" "${_hypr_variables_file}")"
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
if [[ -n "${gtk_theme_path_name}" ]] && [ -d "${THEMES_DIR}/${gtk_theme_path_name}/gtk-4.0" ]; then
  gtk4Theme="${gtk_theme_path_name}"
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

# Ensure the active GTK theme is also available under ~/.themes for apps that
# still look there instead of the XDG theme directory.

if [[ -n "${gtk_theme_path_name}" ]] && [ ! -L "$HOME/.themes/${gtk_theme_path_name}" ] && [ -d "${THEMES_DIR}/${gtk_theme_path_name}" ]; then
  print_log -sec "theme" -warn "linking" "${GTK_THEME} to ~/.themes to fix GTK4 not following xdg"
  mkdir -p "$HOME/.themes"
  rm -rf "$HOME/.themes/${gtk_theme_path_name}"
  ln -snf "${THEMES_DIR}/${gtk_theme_path_name}" "$HOME/.themes/"
fi

# // .Xresources / .Xdefaults
_update_xcursor_resource() {
  local file="$1" create="${2:-false}"
  if [ -f "${file}" ]; then
    sed -i -e "/^Xcursor\.theme:/c\Xcursor.theme: ${CURSOR_THEME}" \
      -e "/^Xcursor\.size:/c\Xcursor.size: ${CURSOR_SIZE}" "${file}"
    grep -q "^Xcursor\.theme:" "${file}" || echo "Xcursor.theme: ${CURSOR_THEME}" >>"${file}"
    grep -q "^Xcursor\.size:" "${file}" || echo "Xcursor.size: ${CURSOR_SIZE}" >>"${file}"
  elif [ "${create}" = true ]; then
    printf 'Xcursor.theme: %s\nXcursor.size: %s\n' "${CURSOR_THEME}" "${CURSOR_SIZE}" >"${file}"
  fi
}
_update_xcursor_resource "$HOME/.Xresources" true
_update_xcursor_resource "$HOME/.Xdefaults"

#? Workaround for gtk-4 having settings.ini!
if [ -f "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini" ]; then
  rm "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini"
fi

#// wallpaper
export -f pkg_installed

apply_theme_wallpaper() {
  local -a wallpaper_args=(
    --wait-lock
    --resume
    --global
    --notify-body "Theme: ${themeSet}"
  )
  if [ "$quiet" = true ]; then
    "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" "${wallpaper_args[@]}" >/dev/null 2>&1
  else
    "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" "${wallpaper_args[@]}"
  fi
}

# Theme mode: apply theme palette and .theme files (wallpaper sets no colors here)
if [[ "${selected_color_mode}" -eq 0 ]]; then
  if [[ "${quiet}" == "true" ]]; then
    "${LIB_DIR}/hypr/theme/theme.apply.sh" --quiet || exit 1
  else
    "${LIB_DIR}/hypr/theme/theme.apply.sh" || exit 1
  fi
else
  apply_theme_wallpaper || exit 1
fi

# Update backend-specific wallpaper links after the primary wallpaper is set,
# so the background processes don't race for the wallpaper lock.
[[ -d "$WALLPAPER_CURRENT_DIR" ]] && find -H "$WALLPAPER_CURRENT_DIR" -name "*.png" -exec sh -c '
    for file; do
        base=$(basename "$file" .png)
        if pkg_installed "${base}"; then
            "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" --link --backend "${base}"
        fi
    done
' sh {} + &

#// nvim sync (after wallpaper/colors so pywal theme reads correct colors)
if [[ -x "${HYPR_LIB_DIR}/util/nvim-theme-sync.sh" ]]; then
  "${HYPR_LIB_DIR}/util/nvim-theme-sync.sh" >/dev/null 2>&1 || true
fi

theme_thumbs_precache
theme_colors_precache
