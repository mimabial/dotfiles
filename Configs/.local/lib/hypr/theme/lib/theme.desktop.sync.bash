#!/usr/bin/env bash

# Shared desktop-theme sync helpers.
#
# This library is the single owner for desktop-facing theme writes:
#   - GTK, Qt, KDE, cursor resource files
#   - GNOME dconf theme state
#   - portal restarts after GTK/dconf changes
#
# Callers should source runtime/init.bash and load state/system modules first.

theme_desktop_ini_write_batch() {
  local config_file="$1"
  shift
  local entry=""
  local group=""
  local rest=""
  local key=""
  local value=""

  for entry in "$@"; do
    group="${entry%%:*}"
    rest="${entry#*:}"
    key="${rest%%=*}"
    value="${rest#*=}"
    ini_write "${config_file}" "${group}" "${key}" "${value}" || return 1
  done
}

theme_desktop_safe_hyq_source() {
  local hyq_output="$1"
  local allowed_vars='^__(GTK_THEME|ICON_THEME|COLOR_SCHEME|CURSOR_THEME|CURSOR_SIZE|TERMINAL|FONT|FONT_SIZE|FONT_STYLE|DOCUMENT_FONT|DOCUMENT_FONT_SIZE|MONOSPACE_FONT|MONOSPACE_FONT_SIZE|BUTTON_LAYOUT|FONT_ANTIALIASING|FONT_HINTING|KDE_COLOR_SCHEME)='
  local validated_output=""
  local line=""

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" =~ ${allowed_vars} ]] || continue
    [[ ! "${line}" =~ \$\(|\`|\; ]] || continue
    validated_output+="${line}"$'\n'
  done <<<"${hyq_output}"

  [[ -n "${validated_output}" ]] && source <(printf '%s' "${validated_output}")
}

theme_desktop_source_env_theme() {
  local env_theme_file="${HYPR_CONFIG_HOME}/env-theme"
  # shellcheck source=/dev/null
  [[ -f "${env_theme_file}" ]] && source "${env_theme_file}"
}

theme_desktop_set_defaults() {
  local color_variant=""

  HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr/hyprland.conf}"
  color_variant="$(state_get_color_variant 2>/dev/null || true)"
  resolved_color_variant="${resolved_color_variant:-${color_variant:-dark}}"

  case "${selected_color_mode:-}" in
    0 | 1 | 2 | 3) ;;
    *) selected_color_mode=0 ;;
  esac

  COLOR_SCHEME="prefer-${resolved_color_variant}"
  if [[ "${selected_color_mode}" -ne 0 ]]; then
    GTK_THEME="Pywal16-Gtk"
  fi

  FONT="${FONT:-Cantarell}"
  FONT_SIZE="${FONT_SIZE:-10}"
  DOCUMENT_FONT="${DOCUMENT_FONT:-Cantarell}"
  DOCUMENT_FONT_SIZE="${DOCUMENT_FONT_SIZE:-10}"
  MONOSPACE_FONT="${MONOSPACE_FONT:-JetBrainsMono Nerd Font}"
  MONOSPACE_FONT_SIZE="${MONOSPACE_FONT_SIZE:-9}"
  FONT_ANTIALIASING="${FONT_ANTIALIASING:-rgba}"
  FONT_HINTING="${FONT_HINTING:-}"
  KDE_COLOR_SCHEME="${KDE_COLOR_SCHEME:-colors}"
}

theme_desktop_load_theme_mode_gtk_values() {
  local theme_conf="${HYPR_CONFIG_HOME}/themes/theme.conf"
  local theme_hyq_output=""

  [[ "${selected_color_mode:-1}" -eq 0 ]] || return 0
  [[ -r "${theme_conf}" ]] || return 0
  command -v hyq >/dev/null 2>&1 || return 0

  theme_hyq_output="$(
    hyq "${theme_conf}" --export env --allow-missing \
      -Q '$GTK_THEME[string]' \
      -Q '$ICON_THEME[string]' \
      -Q '$CURSOR_THEME[string]' \
      -Q '$CURSOR_SIZE'
  )"
  theme_desktop_safe_hyq_source "${theme_hyq_output}"
  GTK_THEME="${__GTK_THEME:-$GTK_THEME}"
  ICON_THEME="${__ICON_THEME:-$ICON_THEME}"
  CURSOR_THEME="${__CURSOR_THEME:-$CURSOR_THEME}"
  CURSOR_SIZE="${__CURSOR_SIZE:-$CURSOR_SIZE}"
}

theme_desktop_build_hyq_args() {
  theme_desktop_hyq_args=(
    "${HYPRLAND_CONFIG}"
    --source
    --export env
    -Q '$COLOR_SCHEME[string]'
    -Q '$TERMINAL[string]'
    -Q '$FONT[string]'
    -Q '$FONT_SIZE'
    -Q '$FONT_STYLE[string]'
    -Q '$DOCUMENT_FONT[string]'
    -Q '$DOCUMENT_FONT_SIZE'
    -Q '$MONOSPACE_FONT[string]'
    -Q '$MONOSPACE_FONT_SIZE'
    -Q '$BUTTON_LAYOUT[string]'
    -Q '$FONT_ANTIALIASING[string]'
    -Q '$FONT_HINTING[string]'
    -Q '$KDE_COLOR_SCHEME[string]'
  )

  if [[ "${selected_color_mode:-1}" -ne 0 ]]; then
    theme_desktop_hyq_args+=(
      -Q '$GTK_THEME[string]'
      -Q '$ICON_THEME[string]'
      -Q '$CURSOR_THEME[string]'
      -Q '$CURSOR_SIZE'
    )
  fi
}

theme_desktop_load_config_values() {
  local query_output=""

  [[ -r "${HYPRLAND_CONFIG}" ]] || return 0
  command -v hyq >/dev/null 2>&1 || return 0

  theme_desktop_load_theme_mode_gtk_values
  theme_desktop_build_hyq_args
  query_output="$(hyq "${theme_desktop_hyq_args[@]}")"
  theme_desktop_safe_hyq_source "${query_output}"

  GTK_THEME="${__GTK_THEME:-$GTK_THEME}"
  COLOR_SCHEME="${__COLOR_SCHEME:-$COLOR_SCHEME}"
  ICON_THEME="${__ICON_THEME:-$ICON_THEME}"
  CURSOR_THEME="${__CURSOR_THEME:-$CURSOR_THEME}"
  CURSOR_SIZE="${__CURSOR_SIZE:-$CURSOR_SIZE}"
  TERMINAL="${__TERMINAL:-$TERMINAL}"
  FONT="${__FONT:-$FONT}"
  FONT_SIZE="${__FONT_SIZE:-$FONT_SIZE}"
  FONT_STYLE="${__FONT_STYLE:-$FONT_STYLE}"
  DOCUMENT_FONT="${__DOCUMENT_FONT:-$DOCUMENT_FONT}"
  DOCUMENT_FONT_SIZE="${__DOCUMENT_FONT_SIZE:-$DOCUMENT_FONT_SIZE}"
  MONOSPACE_FONT="${__MONOSPACE_FONT:-$MONOSPACE_FONT}"
  MONOSPACE_FONT_SIZE="${__MONOSPACE_FONT_SIZE:-$MONOSPACE_FONT_SIZE}"
  BUTTON_LAYOUT="${__BUTTON_LAYOUT:-$BUTTON_LAYOUT}"
  FONT_ANTIALIASING="${__FONT_ANTIALIASING:-$FONT_ANTIALIASING}"
  FONT_HINTING="${__FONT_HINTING:-$FONT_HINTING}"
  KDE_COLOR_SCHEME="${__KDE_COLOR_SCHEME:-$KDE_COLOR_SCHEME}"
}

theme_desktop_fill_missing_from_layers() {
  local value=""

  [[ -n "${GTK_THEME}" ]] || GTK_THEME="$(hypr_config_value_from_layers "GTK_THEME" 2>/dev/null || true)"
  [[ -n "${ICON_THEME}" ]] || ICON_THEME="$(hypr_config_value_from_layers "ICON_THEME" 2>/dev/null || true)"
  [[ -n "${CURSOR_THEME}" ]] || CURSOR_THEME="$(hypr_config_value_from_layers "CURSOR_THEME" 2>/dev/null || true)"
  [[ -n "${CURSOR_SIZE}" ]] || CURSOR_SIZE="$(hypr_config_value_from_layers "CURSOR_SIZE" 2>/dev/null || true)"
  [[ -n "${TERMINAL}" ]] || TERMINAL="$(hypr_config_value_from_layers "TERMINAL" 2>/dev/null || true)"
  [[ -n "${FONT}" ]] || FONT="$(hypr_config_value_from_layers "FONT" 2>/dev/null || true)"
  [[ -n "${FONT_SIZE}" ]] || FONT_SIZE="$(hypr_config_value_from_layers "FONT_SIZE" 2>/dev/null || true)"
  [[ -n "${FONT_STYLE}" ]] || FONT_STYLE="$(hypr_config_value_from_layers "FONT_STYLE" 2>/dev/null || true)"
  [[ -n "${DOCUMENT_FONT}" ]] || DOCUMENT_FONT="$(hypr_config_value_from_layers "DOCUMENT_FONT" 2>/dev/null || true)"
  [[ -n "${DOCUMENT_FONT_SIZE}" ]] || DOCUMENT_FONT_SIZE="$(hypr_config_value_from_layers "DOCUMENT_FONT_SIZE" 2>/dev/null || true)"
  [[ -n "${MONOSPACE_FONT}" ]] || MONOSPACE_FONT="$(hypr_config_value_from_layers "MONOSPACE_FONT" 2>/dev/null || true)"
  [[ -n "${MONOSPACE_FONT_SIZE}" ]] || MONOSPACE_FONT_SIZE="$(hypr_config_value_from_layers "MONOSPACE_FONT_SIZE" 2>/dev/null || true)"
  [[ -n "${BUTTON_LAYOUT}" ]] || BUTTON_LAYOUT="$(hypr_config_value_from_layers "BUTTON_LAYOUT" 2>/dev/null || true)"
  [[ -n "${FONT_ANTIALIASING}" ]] || FONT_ANTIALIASING="$(hypr_config_value_from_layers "FONT_ANTIALIASING" 2>/dev/null || true)"
  if [[ -z "${FONT_HINTING+x}" ]] || [[ -z "${FONT_HINTING}" ]]; then
    value="$(hypr_config_value_from_layers "FONT_HINTING" 2>/dev/null || true)"
    [[ -n "${value}" ]] && FONT_HINTING="${value}"
  fi
  [[ -n "${KDE_COLOR_SCHEME}" ]] || KDE_COLOR_SCHEME="$(hypr_config_value_from_layers "KDE_COLOR_SCHEME" 2>/dev/null || true)"
}

theme_desktop_apply_color_scheme_inversion_if_needed() {
  if [[ "${revert_colors:-0}" -eq 1 ]] \
    || [[ "${selected_color_mode:-0}" -eq 2 && "${resolved_color_variant:-}" == "light" ]] \
    || [[ "${selected_color_mode:-0}" -eq 3 && "${resolved_color_variant:-}" == "dark" ]]; then
    if [[ "${resolved_color_variant}" == "dark" ]]; then
      COLOR_SCHEME="prefer-light"
    else
      COLOR_SCHEME="prefer-dark"
    fi
  fi
}

theme_desktop_export_variables() {
  export GTK_THEME ICON_THEME COLOR_SCHEME CURSOR_THEME CURSOR_SIZE TERMINAL \
    FONT FONT_SIZE FONT_STYLE DOCUMENT_FONT DOCUMENT_FONT_SIZE MONOSPACE_FONT \
    MONOSPACE_FONT_SIZE BUTTON_LAYOUT FONT_ANTIALIASING FONT_HINTING KDE_COLOR_SCHEME
}

theme_desktop_resolve_values() {
  if [[ -d /run/current-system/sw/share/themes ]]; then
    THEMES_DIR=/run/current-system/sw/share/themes
    export THEMES_DIR
  fi

  theme_desktop_source_env_theme
  theme_desktop_set_defaults
  theme_desktop_load_config_values
  theme_desktop_fill_missing_from_layers
  theme_desktop_apply_color_scheme_inversion_if_needed
  theme_desktop_export_variables
}

theme_desktop_is_safe_path_component() {
  local value="$1"
  [[ -n "${value}" ]] \
    && [[ "${value}" != "." ]] \
    && [[ "${value}" != ".." ]] \
    && [[ "${value}" != */* ]] \
    && [[ "${value}" != *$'\n'* ]] \
    && [[ "${value}" != *$'\r'* ]]
}

theme_desktop_resolve_gtk_theme_path() {
  theme_desktop_gtk_theme_path_name=""

  if theme_desktop_is_safe_path_component "${GTK_THEME}"; then
    theme_desktop_gtk_theme_path_name="${GTK_THEME}"
  elif [[ -n "${GTK_THEME}" ]]; then
    print_log -sec "theme" -warn "gtk" "unsafe theme path component: ${GTK_THEME}"
  fi

  if [[ -n "${theme_desktop_gtk_theme_path_name}" ]] \
    && [[ ! -d "${THEMES_DIR}/${theme_desktop_gtk_theme_path_name}" ]] \
    && [[ -d "${HOME}/.themes/${theme_desktop_gtk_theme_path_name}" ]]; then
    cp -rns "${HOME}/.themes/${theme_desktop_gtk_theme_path_name}" "${THEMES_DIR}/${theme_desktop_gtk_theme_path_name}"
  fi
}

theme_desktop_update_xcursor_resource() {
  local file="$1"
  local create="${2:-false}"

  if [[ -f "${file}" ]]; then
    sed -i \
      -e "/^Xcursor\\.theme:/c\\Xcursor.theme: ${CURSOR_THEME}" \
      -e "/^Xcursor\\.size:/c\\Xcursor.size: ${CURSOR_SIZE}" \
      "${file}"
    grep -q "^Xcursor\\.theme:" "${file}" || echo "Xcursor.theme: ${CURSOR_THEME}" >>"${file}"
    grep -q "^Xcursor\\.size:" "${file}" || echo "Xcursor.size: ${CURSOR_SIZE}" >>"${file}"
  elif [[ "${create}" == "true" ]]; then
    printf 'Xcursor.theme: %s\nXcursor.size: %s\n' "${CURSOR_THEME}" "${CURSOR_SIZE}" >"${file}"
  fi
}

theme_desktop_resolve_terminal_command() {
  local variables_file=""

  [[ -n "${TERMINAL}" ]] && return 0
  variables_file="$(hypr_variables_file 2>/dev/null || printf '%s\n' "${HYPR_DATA_HOME}/variables.conf")"
  TERMINAL="$(get_hypr_conf "TERMINAL" "${variables_file}" 2>/dev/null || true)"
}

theme_desktop_apply_cursor_theme() {
  if [[ -n "${CURSOR_THEME}" ]] && [[ -n "${CURSOR_SIZE}" ]] && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    if ! hyprctl setcursor "${CURSOR_THEME}" "${CURSOR_SIZE}" >/dev/null 2>&1; then
      print_log -sec "theme" -warn "cursor" "failed to apply ${CURSOR_THEME} (${CURSOR_SIZE})"
    fi
  fi
}

theme_desktop_set_cursor_async() {
  [[ -n "${CURSOR_THEME}" && -n "${CURSOR_SIZE}" ]] || return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  hyprctl setcursor "${CURSOR_THEME}" "${CURSOR_SIZE}" >/dev/null 2>&1 &
}

theme_desktop_configure_qt() {
  local qt_font_style=""

  QT5_FONT="${QT5_FONT:-${FONT}}"
  QT5_FONT_SIZE="${QT5_FONT_SIZE:-${FONT_SIZE}}"
  QT5_MONOSPACE_FONT="${QT5_MONOSPACE_FONT:-${MONOSPACE_FONT}}"
  QT5_MONOSPACE_FONT_SIZE="${QT5_MONOSPACE_FONT_SIZE:-${MONOSPACE_FONT_SIZE:-9}}"
  QT6_FONT="${QT6_FONT:-${FONT}}"
  QT6_FONT_SIZE="${QT6_FONT_SIZE:-${FONT_SIZE}}"
  QT6_MONOSPACE_FONT="${QT6_MONOSPACE_FONT:-${MONOSPACE_FONT}}"
  QT6_MONOSPACE_FONT_SIZE="${QT6_MONOSPACE_FONT_SIZE:-${MONOSPACE_FONT_SIZE:-9}}"
  qt_font_style="${QT_FONT_STYLE:-${FONT_STYLE:-Normal}}"

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/qt5ct/qt5ct.conf" \
    "Appearance:icon_theme=${ICON_THEME}" \
    "Fonts:general=\"${QT5_FONT},${QT5_FONT_SIZE},-1,5,50,0,0,0,0,0,${qt_font_style}\"" \
    "Fonts:fixed=\"${QT5_MONOSPACE_FONT},${QT5_MONOSPACE_FONT_SIZE},-1,5,50,0,0,0,0,0\""

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/qt6ct/qt6ct.conf" \
    "Appearance:icon_theme=${ICON_THEME}" \
    "Fonts:general=\"${QT6_FONT},${QT6_FONT_SIZE},-1,5,400,0,0,0,0,0,0,0,0,0,0,1,${qt_font_style}\"" \
    "Fonts:fixed=\"${QT6_MONOSPACE_FONT},${QT6_MONOSPACE_FONT_SIZE:-9},-1,5,400,0,0,0,0,0,0,0,0,0,0,1\""
}

theme_desktop_configure_kde() {
  local -a kdeglobals_entries=()
  local scheme_dir=""
  local kde_color_scheme_file=""

  theme_desktop_resolve_terminal_command
  kdeglobals_entries=(
    "Icons:Theme=${ICON_THEME}"
    "KDE:widgetStyle=kvantum"
  )

  KDE_COLOR_SCHEME="${KDE_COLOR_SCHEME:-colors}"
  for scheme_dir in "${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes" "/usr/share/color-schemes"; do
    if [[ -f "${scheme_dir}/${KDE_COLOR_SCHEME}.colors" ]]; then
      kde_color_scheme_file="${scheme_dir}/${KDE_COLOR_SCHEME}.colors"
      break
    fi
  done

  if [[ -n "${kde_color_scheme_file}" ]]; then
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

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/kdeglobals" "${kdeglobals_entries[@]}"
}

theme_desktop_configure_default_cursor_theme() {
  theme_desktop_ini_write_batch "${XDG_DATA_HOME}/icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}"
  theme_desktop_ini_write_batch "${HOME}/.icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}"
}

theme_desktop_configure_gtk() {
  local gtk3_font=""
  local gtk3_font_size=""
  local gtk4_theme=""
  local gtkrc_file="${HOME}/.gtkrc-2.0"
  local xsettingsd_file="${XDG_CONFIG_HOME}/xsettingsd/xsettingsd.conf"

  gtk3_font="${GTK3_FONT:-${FONT}}"
  gtk3_font_size="${GTK3_FONT_SIZE:-${FONT_SIZE}}"

  mkdir -p "${XDG_CONFIG_HOME}/gtk-3.0" "${XDG_CONFIG_HOME}/xsettingsd"
  touch "${gtkrc_file}" "${xsettingsd_file}"

  sed -i \
    -e "/^gtk-theme-name=/c\\gtk-theme-name=\"${GTK_THEME}\"" \
    -e "/^include /c\\include \"$HOME/.gtkrc-2.0.mime\"" \
    -e "/^gtk-cursor-theme-name=/c\\gtk-cursor-theme-name=\"${CURSOR_THEME}\"" \
    -e "/^gtk-icon-theme-name=/c\\gtk-icon-theme-name=\"${ICON_THEME}\"" \
    "${gtkrc_file}"
  grep -q '^gtk-theme-name=' "${gtkrc_file}" || echo "gtk-theme-name=\"${GTK_THEME}\"" >>"${gtkrc_file}"
  grep -q '^include ' "${gtkrc_file}" || echo "include \"$HOME/.gtkrc-2.0.mime\"" >>"${gtkrc_file}"
  grep -q '^gtk-cursor-theme-name=' "${gtkrc_file}" || echo "gtk-cursor-theme-name=\"${CURSOR_THEME}\"" >>"${gtkrc_file}"
  grep -q '^gtk-icon-theme-name=' "${gtkrc_file}" || echo "gtk-icon-theme-name=\"${ICON_THEME}\"" >>"${gtkrc_file}"

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/gtk-3.0/settings.ini" \
    "Settings:gtk-theme-name=${GTK_THEME}" \
    "Settings:gtk-icon-theme-name=${ICON_THEME}" \
    "Settings:gtk-cursor-theme-name=${CURSOR_THEME}" \
    "Settings:gtk-cursor-theme-size=${CURSOR_SIZE}" \
    "Settings:gtk-font-name=${gtk3_font} ${gtk3_font_size}"

  if [[ -n "${theme_desktop_gtk_theme_path_name}" ]] && [[ -d "${THEMES_DIR}/${theme_desktop_gtk_theme_path_name}/gtk-4.0" ]]; then
    gtk4_theme="${theme_desktop_gtk_theme_path_name}"
  else
    gtk4_theme="Pywal16-Gtk"
    print_log -sec "theme" -stat "use" "'Pywal16-Gtk' as gtk4 theme"
  fi

  rm -rf "${XDG_CONFIG_HOME}/gtk-4.0"
  if [[ -d "${THEMES_DIR}/${gtk4_theme}/gtk-4.0" ]]; then
    ln -s "${THEMES_DIR}/${gtk4_theme}/gtk-4.0" "${XDG_CONFIG_HOME}/gtk-4.0"
  else
    print_log -sec "theme" -warn "gtk4" "theme directory '${THEMES_DIR}/${gtk4_theme}/gtk-4.0' does not exist"
  fi

  if pkg_installed flatpak; then
    flatpak \
      --user override \
      --filesystem="${THEMES_DIR}" \
      --filesystem="${HOME}/.themes" \
      --filesystem="${HOME}/.icons" \
      --filesystem="${XDG_DATA_HOME:-$HOME/.local/share}/icons" \
      --env=GTK_THEME="${gtk4_theme}" \
      --env=ICON_THEME="${ICON_THEME}"
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 &
  fi

  sed -i \
    -e "/^Net\\/ThemeName /c\\Net\\/ThemeName \"${GTK_THEME}\"" \
    -e "/^Net\\/IconThemeName /c\\Net\\/IconThemeName \"${ICON_THEME}\"" \
    -e "/^Gtk\\/CursorThemeName /c\\Gtk\\/CursorThemeName \"${CURSOR_THEME}\"" \
    -e "/^Gtk\\/CursorThemeSize /c\\Gtk\\/CursorThemeSize ${CURSOR_SIZE}" \
    "${xsettingsd_file}"
  grep -q '^Net/ThemeName ' "${xsettingsd_file}" || echo "Net/ThemeName \"${GTK_THEME}\"" >>"${xsettingsd_file}"
  grep -q '^Net/IconThemeName ' "${xsettingsd_file}" || echo "Net/IconThemeName \"${ICON_THEME}\"" >>"${xsettingsd_file}"
  grep -q '^Gtk/CursorThemeName ' "${xsettingsd_file}" || echo "Gtk/CursorThemeName \"${CURSOR_THEME}\"" >>"${xsettingsd_file}"
  grep -q '^Gtk/CursorThemeSize ' "${xsettingsd_file}" || echo "Gtk/CursorThemeSize ${CURSOR_SIZE}" >>"${xsettingsd_file}"

  if [[ -n "${theme_desktop_gtk_theme_path_name}" ]] \
    && [[ ! -L "${HOME}/.themes/${theme_desktop_gtk_theme_path_name}" ]] \
    && [[ -d "${THEMES_DIR}/${theme_desktop_gtk_theme_path_name}" ]]; then
    print_log -sec "theme" -warn "linking" "${GTK_THEME} to ~/.themes to fix GTK4 not following xdg"
    mkdir -p "${HOME}/.themes"
    rm -rf "${HOME}/.themes/${theme_desktop_gtk_theme_path_name}"
    ln -snf "${THEMES_DIR}/${theme_desktop_gtk_theme_path_name}" "${HOME}/.themes/"
  fi

  [[ -f "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini" ]] && rm "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini"
}

theme_desktop_configure_xcursor_resources() {
  theme_desktop_update_xcursor_resource "${HOME}/.Xresources" true
  theme_desktop_update_xcursor_resource "${HOME}/.Xdefaults"
}

theme_desktop_dconf_payload() {
  cat <<EOF
[org/gnome/desktop/interface]
icon-theme='${ICON_THEME}'
gtk-theme='${GTK_THEME}'
color-scheme='${COLOR_SCHEME}'
cursor-theme='${CURSOR_THEME}'
cursor-size=${CURSOR_SIZE}
font-name='${FONT} ${FONT_SIZE}'
document-font-name='${DOCUMENT_FONT} ${DOCUMENT_FONT_SIZE}'
monospace-font-name='${MONOSPACE_FONT} ${MONOSPACE_FONT_SIZE}'
font-antialiasing='${FONT_ANTIALIASING}'
font-hinting='${FONT_HINTING}'

[org/gnome/desktop/default-applications/terminal]
exec='$(command -v "${TERMINAL}")'

[org/gnome/desktop/wm/preferences]
button-layout='${BUTTON_LAYOUT}'
EOF
}

theme_desktop_write_dconf_content() {
  local dconf_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/dconf"
  local dconf_tmp=""
  local new_content=""
  local new_hash=""
  local old_hash=""
  theme_desktop_dconf_content_changed=0

  mkdir -p "$(dirname "${dconf_file}")"
  new_content="$(theme_desktop_dconf_payload)"
  new_hash="$(printf '%s' "${new_content}" | md5sum | cut -d' ' -f1)"
  [[ -f "${dconf_file}" ]] && old_hash="$(md5sum "${dconf_file}" 2>/dev/null | cut -d' ' -f1)"

  if [[ "${new_hash}" == "${old_hash}" ]]; then
    print_log -sec "dconf" -stat "skip" "unchanged"
    return 0
  fi

  dconf_tmp="$(mktemp "${dconf_file}.tmp.XXXXXX")" || return 1
  printf '%s\n' "${new_content}" >"${dconf_tmp}" || {
    rm -f "${dconf_tmp}"
    return 1
  }

  if dconf load -f / <"${dconf_tmp}" >/dev/null 2>&1; then
    mv -f "${dconf_tmp}" "${dconf_file}"
    theme_desktop_dconf_content_changed=1
    print_log -sec "dconf" -stat "loaded" "${dconf_file}"
  else
    rm -f "${dconf_tmp}"
    print_log -sec "dconf" -warn "failed" "${dconf_file}"
  fi
}

theme_desktop_restart_portal_backends_if_needed() {
  local portal_reset_script="${LIB_DIR}/hypr/system/reset-xdg-portal.sh"

  [[ "${theme_desktop_dconf_content_changed:-0}" -eq 1 ]] || return 0
  [[ -x "${portal_reset_script}" ]] || return 0

  "${portal_reset_script}" >/dev/null 2>&1 \
    && print_log -sec "dconf" -stat "portal" "restarted" \
    || print_log -sec "dconf" -warn "portal" "restart failed"
}

theme_desktop_log_dconf_result() {
  [[ "${THEME_DESKTOP_SYNC_LOG_DCONF:-1}" -eq 1 ]] || return 0
  print_log -sec "dconf" -stat "Loaded dconf settings" "::"
  print_log -y "#-----------------------------------------------#"
  theme_desktop_dconf_payload
  print_log -y "#-----------------------------------------------#"
}

theme_desktop_sync_runtime() {
  theme_desktop_resolve_values
  theme_desktop_write_dconf_content
  theme_desktop_restart_portal_backends_if_needed
  theme_desktop_set_cursor_async
  theme_desktop_log_dconf_result
}

theme_desktop_sync_static() {
  theme_desktop_resolve_values
  theme_desktop_resolve_gtk_theme_path
  theme_desktop_configure_qt
  theme_desktop_configure_kde
  theme_desktop_configure_default_cursor_theme
  theme_desktop_configure_gtk
  theme_desktop_configure_xcursor_resources
}

theme_desktop_sync_full() {
  theme_desktop_resolve_values
  theme_desktop_resolve_gtk_theme_path
  theme_desktop_configure_qt
  theme_desktop_configure_kde
  theme_desktop_configure_default_cursor_theme
  theme_desktop_configure_gtk
  theme_desktop_configure_xcursor_resources
  theme_desktop_write_dconf_content
  theme_desktop_restart_portal_backends_if_needed
  theme_desktop_apply_cursor_theme
  theme_desktop_log_dconf_result
}
