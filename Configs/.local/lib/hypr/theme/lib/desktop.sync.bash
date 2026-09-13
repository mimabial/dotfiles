#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

if ! declare -F hypr_hash_cache_runtime_file >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${LIB_DIR:-$HOME/.local/lib}/hypr/core/hash-cache.sh" || return 1 2>/dev/null || exit 1
fi

theme_desktop_ini_write_batch() {
  local config_file="$1"
  shift
  local entry="" rest=""

  {
    for entry in "$@"; do
      rest="${entry#*:}"
      printf '%s\t%s\t%s\n' "${entry%%:*}" "${rest%%=*}" "${rest#*=}"
    done
  } | ini_write_multi "${config_file}"
}

theme_desktop_write_generated_file() {
  local target_file="$1"
  local target_dir=""
  local target_name=""
  local tmp_file=""

  target_dir="${target_file%/*}"
  target_name="${target_file##*/}"
  mkdir -p "${target_dir}" || return 1
  tmp_file="$(mktemp "${target_dir}/.${target_name}.XXXXXX")" || return 1
  cat >"${tmp_file}" || {
    rm -f -- "${tmp_file}"
    return 1
  }

  if [[ -f "${target_file}" ]] && cmp -s "${tmp_file}" "${target_file}"; then
    rm -f -- "${tmp_file}"
    return 0
  fi

  mv -f -- "${tmp_file}" "${target_file}"
}

theme_desktop_load_looknfeel_cursor_values() {
  local theme_slug=""
  local override_file=""
  local -A looknfeel_values=()

  [[ -n "${HYPR_THEME:-}" ]] || return 0
  theme_slug="$(LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' <<<"${HYPR_THEME,,}")"
  [[ -n "${theme_slug}" ]] || theme_slug="default"
  override_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/looknfeel.d/${theme_slug}.${resolved_color_variant:-dark}.lua"

  hypr_config_parse_layer_file "${override_file}" looknfeel_values
  [[ -n "${looknfeel_values[CURSOR_THEME]-}" ]] \
    && CURSOR_THEME="${looknfeel_values[CURSOR_THEME]}"
  [[ -n "${looknfeel_values[CURSOR_SIZE]-}" ]] \
    && CURSOR_SIZE="${looknfeel_values[CURSOR_SIZE]}"
  return 0
}

declare -ga theme_desktop_layered_vars=(
  ICON_THEME
  CURSOR_THEME
  CURSOR_SIZE
  TERMINAL
  FONT
  FONT_SIZE
  DOCUMENT_FONT
  DOCUMENT_FONT_SIZE
  MONOSPACE_FONT
  MONOSPACE_FONT_SIZE
  BUTTON_LAYOUT
  FONT_ANTIALIASING
  FONT_HINTING
)

theme_desktop_resolve_base_values() {
  local env_theme_file="${HYPR_CONFIG_HOME}/env-theme"
  local layer_var=""
  local layer_value=""
  local -a layer_files=()
  local -A userfonts_values=()
  local -A variables_values=()
  local -A theme_meta_values=()

  mapfile -t layer_files < <(hypr_config_layer_files)
  for layer_var in "${theme_desktop_layered_vars[@]}"; do printf -v "${layer_var}" %s ""; done
  # shellcheck source=/dev/null
  [[ -f "${env_theme_file}" ]] && source "${env_theme_file}"
  hypr_config_parse_layer_file "${layer_files[0]}" userfonts_values
  hypr_config_parse_layer_file "${layer_files[1]}" theme_meta_values
  hypr_config_parse_layer_file "${layer_files[2]}" variables_values
  for layer_var in "${theme_desktop_layered_vars[@]}"; do
    [[ -n "${!layer_var-}" ]] && continue
    layer_value="${userfonts_values[${layer_var}]-}"
    [[ -n "${layer_value}" ]] || layer_value="${theme_meta_values[${layer_var}]-}"
    [[ -n "${layer_value}" ]] || layer_value="${variables_values[${layer_var}]-}"
    [[ -n "${layer_value}" ]] && printf -v "${layer_var}" '%s' "${layer_value}"
  done

  if [[ "${selected_color_source:-theme}" == "theme" ]]; then
    for layer_var in ICON_THEME CURSOR_THEME CURSOR_SIZE; do
      layer_value="${theme_meta_values[${layer_var}]-}"
      [[ -n "${layer_value}" ]] && printf -v "${layer_var}" %s "${layer_value}"
    done
  fi

  FONT="${FONT:-Cantarell}"
  FONT_SIZE="${FONT_SIZE:-10}"
  DOCUMENT_FONT="${DOCUMENT_FONT:-Cantarell}"
  DOCUMENT_FONT_SIZE="${DOCUMENT_FONT_SIZE:-10}"
  MONOSPACE_FONT="${MONOSPACE_FONT:-JetBrainsMono Nerd Font}"
  MONOSPACE_FONT_SIZE="${MONOSPACE_FONT_SIZE:-10}"
  FONT_ANTIALIASING="${FONT_ANTIALIASING:-rgba}"
  return 0
}

theme_desktop_resolve_values() {
  local color_variant=""

  if [[ -d /run/current-system/sw/share/themes ]]; then
    THEMES_DIR=/run/current-system/sw/share/themes
    export THEMES_DIR
  fi

  HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua}"
  color_variant="$(state_get_color_variant 2>/dev/null || true)"
  resolved_color_variant="${resolved_color_variant:-${color_variant:-dark}}"

  selected_color_source="$(state_resolve_color_source "${selected_color_source:-}" "${selected_color_mode:-}")"
  selected_color_mode="$(state_resolve_color_mode "${selected_color_mode:-}" "${resolved_color_variant}")"

  COLOR_SCHEME="prefer-${resolved_color_variant}"
  theme_desktop_resolve_base_values
  theme_desktop_load_looknfeel_cursor_values

  if [[ "${revert_colors:-0}" -eq 1 ]] \
    || [[ "${selected_color_mode:-0}" -eq 2 && "${resolved_color_variant:-}" == "light" ]] \
    || [[ "${selected_color_mode:-0}" -eq 3 && "${resolved_color_variant:-}" == "dark" ]]; then
    if [[ "${resolved_color_variant}" == "dark" ]]; then
      COLOR_SCHEME="prefer-light"
    else
      COLOR_SCHEME="prefer-dark"
    fi
  fi

  local resolved_gtk="Adwaita"
  local pack_dir="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME:-}"
  local pywal_gtk_dir="${XDG_DATA_HOME:-$HOME/.local/share}/themes/Pywal16-Gtk"
  if [[ -n "${HYPR_THEME:-}" && (-d "${pack_dir}/gtk-3.0" || -d "${pack_dir}/gtk-4.0") ]]; then
    resolved_gtk="${HYPR_THEME// /-}"
    mkdir -p "${HOME}/.themes"
    ln -snf "${pack_dir}" "${HOME}/.themes/${resolved_gtk}" || true
  elif [[ -f "${pywal_gtk_dir}/gtk-3.0/gtk.css" || -f "${pywal_gtk_dir}/gtk-4.0/gtk.css" ]]; then
    resolved_gtk="Pywal16-Gtk"
  fi

  RESOLVED_GTK_THEME="${resolved_gtk}"
  RESOLVED_KVANTUM_THEME="$(theme_desktop_kvantum_output_theme_name)"

  if [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/Pywal.colors" ]]; then
    RESOLVED_KDE_COLOR_SCHEME="Pywal"
  elif [[ "${COLOR_SCHEME}" == "prefer-light" ]]; then
    RESOLVED_KDE_COLOR_SCHEME="KvGnome"
  else
    RESOLVED_KDE_COLOR_SCHEME="KvGnomeDark"
  fi
  RESOLVED_KDE_WIDGET_STYLE="kvantum"

  export ICON_THEME COLOR_SCHEME CURSOR_THEME CURSOR_SIZE TERMINAL \
    FONT FONT_SIZE DOCUMENT_FONT DOCUMENT_FONT_SIZE MONOSPACE_FONT \
    MONOSPACE_FONT_SIZE BUTTON_LAYOUT FONT_ANTIALIASING FONT_HINTING \
    RESOLVED_KVANTUM_THEME RESOLVED_KDE_COLOR_SCHEME RESOLVED_KDE_WIDGET_STYLE
}

theme_desktop_update_xcursor_resource() {
  local file="$1"
  local create="${2:-false}"

  if [[ ! -f "${file}" ]]; then
    [[ "${create}" == "true" ]] || return 0
    printf 'Xcursor.theme: %s\nXcursor.size: %s\n' "${CURSOR_THEME}" "${CURSOR_SIZE}" |
      theme_desktop_write_generated_file "${file}"
    return
  fi

  awk -v theme="${CURSOR_THEME}" -v size="${CURSOR_SIZE}" '
    /^Xcursor\.theme:/ { if (!seen_theme++) print "Xcursor.theme: " theme; next }
    /^Xcursor\.size:/ { if (!seen_size++) print "Xcursor.size: " size; next }
    { print }
    END {
      if (!seen_theme) print "Xcursor.theme: " theme
      if (!seen_size) print "Xcursor.size: " size
    }
  ' "${file}" | theme_desktop_write_generated_file "${file}"
}

theme_desktop_export_cursor_environment() {
  local xcursor_path=""

  [[ -n "${CURSOR_THEME}" && -n "${CURSOR_SIZE}" ]] || return 0

  xcursor_path="${XCURSOR_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/icons:$HOME/.icons:/usr/share/icons}"
  export XCURSOR_THEME="${CURSOR_THEME}"
  export XCURSOR_SIZE="${CURSOR_SIZE}"
  export HYPRCURSOR_THEME="${CURSOR_THEME}"
  export HYPRCURSOR_SIZE="${CURSOR_SIZE}"
  export XCURSOR_PATH="${xcursor_path}"

  if command -v uwsm >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    uwsm finalize \
      "XCURSOR_THEME=${XCURSOR_THEME}" \
      "XCURSOR_SIZE=${XCURSOR_SIZE}" \
      "HYPRCURSOR_THEME=${HYPRCURSOR_THEME}" \
      "HYPRCURSOR_SIZE=${HYPRCURSOR_SIZE}" \
      "XCURSOR_PATH=${XCURSOR_PATH}" >/dev/null 2>&1 ||
      print_log -sec "theme" -warn "cursor" "failed to update UWSM cursor environment"
  fi

  theme_desktop_export_activation_env cursor \
    XCURSOR_THEME XCURSOR_SIZE HYPRCURSOR_THEME HYPRCURSOR_SIZE XCURSOR_PATH
}

theme_desktop_export_activation_env() {
  local name="$1"
  local -a flags=()
  shift

  command -v dbus-update-activation-environment >/dev/null 2>&1 || return 0
  [[ -d /run/systemd/system ]] && flags=(--systemd)
  dbus-update-activation-environment "${flags[@]}" "$@" >/dev/null 2>&1 ||
    print_log -sec "theme" -warn "${name}" "failed to update activation environment"
}

theme_desktop_export_session_qt_env() {
  local qt_env_file="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/qt-session.env"
  [[ -r "${qt_env_file}" ]] || return 0

  local -a qt_pairs=()
  local line=""
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    qt_pairs+=("${line}")
  done <"${qt_env_file}"
  [[ ${#qt_pairs[@]} -gt 0 ]] || return 0

  theme_desktop_export_activation_env qt-env "${qt_pairs[@]}"
}

theme_desktop_resolve_instance_signature() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && return 0
  declare -F refresh_hypr_instance_signature >/dev/null 2>&1 || return 1
  refresh_hypr_instance_signature
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]
}

theme_desktop_sanitize_cursor_theme_index() {
  local dir=""
  local index=""

  for dir in "${XDG_DATA_HOME:-$HOME/.local/share}/icons" "${HOME}/.icons"; do
    index="${dir}/${CURSOR_THEME}/index.theme"
    [[ -f "${index}" && -w "${index}" ]] || continue
    grep -qiE '^[[:space:]]*Inherits[[:space:]]*=[[:space:]]*"?default"?[[:space:]]*$' "${index}" || continue
    sed -i -E '/^[[:space:]]*Inherits[[:space:]]*=[[:space:]]*"?default"?[[:space:]]*$/d' "${index}"
    print_log -sec "theme" -stat "cursor" "removed Inherits=default cycle from ${index}"
  done
}

theme_desktop_apply_cursor_theme() {
  [[ -n "${CURSOR_THEME}" && -n "${CURSOR_SIZE}" ]] || return 0
  theme_desktop_resolve_instance_signature || return 0
  theme_desktop_sanitize_cursor_theme_index
  if ! HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE}" \
    hyprctl setcursor "${CURSOR_THEME}" "${CURSOR_SIZE}" >/dev/null 2>&1; then
    print_log -sec "theme" -warn "cursor" "failed to apply ${CURSOR_THEME} (${CURSOR_SIZE})"
  fi
}

theme_desktop_set_cursor_async() {
  [[ -n "${CURSOR_THEME}" && -n "${CURSOR_SIZE}" ]] || return 0
  theme_desktop_resolve_instance_signature || return 0
  theme_desktop_sanitize_cursor_theme_index
  HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE}" \
    hyprctl setcursor "${CURSOR_THEME}" "${CURSOR_SIZE}" >/dev/null 2>&1 &
}

theme_desktop_kvantum_output_theme_name() {
  printf '%s' "pywal16"
}

theme_desktop_kvantum_shell_dir() {
  HYPR_THEME="${HYPR_THEME:-}" python3 "${LIB_DIR}/hypr/render/_shell.py" 2>/dev/null
}

theme_desktop_install_kvantum_theme() {
  local installer="${LIB_DIR}/hypr/theme/lib/install_kvantum_theme.py"
  local active_palette="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/active-palette.json"
  local kvantum_theme=""
  local dest_dir=""
  local shell_dir=""

  shell_dir="$(theme_desktop_kvantum_shell_dir)"
  [[ -f "${shell_dir}/shell.svg" && -f "${shell_dir}/shell.kvconfig" ]] || return 0

  kvantum_theme="$(theme_desktop_kvantum_output_theme_name)"
  dest_dir="${XDG_CONFIG_HOME}/Kvantum/${kvantum_theme}"

  mkdir -p "${dest_dir}" || return 1
  cp -f "${shell_dir}/shell.svg" "${dest_dir}/${kvantum_theme}.svg" || return 1
  cp -f "${shell_dir}/shell.kvconfig" "${dest_dir}/${kvantum_theme}.kvconfig" || return 1

  ACTIVE_PALETTE_JSON="${active_palette}" \
    HYPR_THEME="${HYPR_THEME:-}" \
    SVG_PATH="${dest_dir}/${kvantum_theme}.svg" \
    KVCONFIG_PATH="${dest_dir}/${kvantum_theme}.kvconfig" \
    python3 "${installer}" || return 1
}

theme_desktop_install_file() {
  local source_file="$1"
  local target_file="$2"
  [[ -f "${source_file}" ]] || return 0
  mkdir -p "${target_file%/*}" || return 1
  if [[ -f "${target_file}" ]] && cmp -s "${source_file}" "${target_file}"; then
    return 0
  fi
  cp -f -- "${source_file}" "${target_file}"
}

theme_desktop_install_kde_color_scheme() {
  theme_desktop_install_file \
    "${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/Pywal.colors" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/Pywal.colors"
}

theme_desktop_install_kdeglobals_color_sections() {
  local target_file="$1"
  local source_file="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/Pywal.colors"
  local line=""
  local section=""
  local key=""
  local value=""
  local records=""

  [[ -n "${target_file}" ]] || return 1
  [[ -f "${source_file}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"

    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line}" == \#* || "${line}" == \;* ]] && continue

    if [[ "${line}" == \[*\] ]]; then
      section="${line#\[}"
      section="${section%\]}"
      continue
    fi

    case "${section}" in
      Colors:*|ColorEffects:*|KDE|WM) ;;
      *) continue ;;
    esac

    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ -n "${key}" ]] || continue

    records+="${section}"$'\t'"${key}"$'\t'"${value}"$'\n'
  done <"${source_file}"

  [[ -n "${records}" ]] || return 0

  printf '%s' "${records}" | ini_write_multi "${target_file}" || return 1
}

theme_desktop_install_qtct_color_scheme() {
  theme_desktop_install_file \
    "${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/pywal16.conf" \
    "${XDG_CONFIG_HOME}/qt6ct/colors/pywal16.conf"
}

theme_desktop_configure_qt_kde_bridge() {
  local qt6ct_color_scheme="${XDG_CONFIG_HOME}/qt6ct/colors/pywal16.conf"
  local base_px=12 base_pt=10 text_size=""
  local ui_size="10.00" fixed_size="10.00"

  # Match Quickshell's px-to-point conversion.
  text_size="$(state_get TEXT_SIZE "${base_px}" 2>/dev/null || true)"
  if [[ ${text_size} =~ ^[0-9]+$ ]]; then
    ui_size="$(awk -v size="${text_size}" -v pt="${base_pt}" -v base="${base_px}" \
      'BEGIN { printf "%.2f", size * pt / base }')"
    fixed_size="${ui_size}"
  fi

  local qt6ct_general_font="${FONT},${ui_size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
  local qt6ct_fixed_font="${MONOSPACE_FONT},${fixed_size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"

  theme_desktop_write_generated_file "${XDG_CONFIG_HOME}/Kvantum/kvantum.kvconfig" <<EOF || return 1
[General]
theme=${RESOLVED_KVANTUM_THEME}
EOF

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/kdeglobals" \
    "General:ColorScheme=${RESOLVED_KDE_COLOR_SCHEME}" \
    "Icons:Theme=${ICON_THEME}" \
    "KDE:widgetStyle=${RESOLVED_KDE_WIDGET_STYLE:-kvantum}" \
    "UiSettings:ColorScheme=${RESOLVED_KDE_COLOR_SCHEME}" || return 1

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/kdedefaults/kdeglobals" \
    "General:ColorScheme=${RESOLVED_KDE_COLOR_SCHEME}" \
    "Icons:Theme=${ICON_THEME}" \
    "KDE:widgetStyle=${RESOLVED_KDE_WIDGET_STYLE:-kvantum}" || return 1

  if [[ "${RESOLVED_KDE_COLOR_SCHEME:-}" == "Pywal" ]]; then
    theme_desktop_install_kdeglobals_color_sections "${XDG_CONFIG_HOME}/kdeglobals" || return 1
    theme_desktop_install_kdeglobals_color_sections "${XDG_CONFIG_HOME}/kdedefaults/kdeglobals" || return 1
  fi

  theme_desktop_write_generated_file "${XDG_CONFIG_HOME}/qt6ct/qt6ct.conf" <<EOF
[Appearance]
color_scheme_path=${qt6ct_color_scheme}
custom_palette=true
icon_theme=${ICON_THEME}
standard_dialogs=default
style=${RESOLVED_KDE_WIDGET_STYLE:-kvantum}

[Interface]
stylesheets=@Invalid()

[Fonts]
fixed="${qt6ct_fixed_font}"
general="${qt6ct_general_font}"
EOF
}

# GTK3 and GTK4 take the same key set; only the file differs.
theme_desktop_write_gtk_settings() {
  local settings_file="$1"
  local prefer_dark="$2"
  local gtk3_font="$3"
  local gtk3_font_size="$4"

  mkdir -p "${settings_file%/*}" || return 1
  theme_desktop_ini_write_batch "${settings_file}" \
    "Settings:gtk-theme-name=${RESOLVED_GTK_THEME}" \
    "Settings:gtk-icon-theme-name=${ICON_THEME}" \
    "Settings:gtk-cursor-theme-name=${CURSOR_THEME}" \
    "Settings:gtk-cursor-theme-size=${CURSOR_SIZE}" \
    "Settings:gtk-font-name=${gtk3_font} ${gtk3_font_size}" \
    "Settings:gtk-application-prefer-dark-theme=${prefer_dark}"
}

theme_desktop_write_gtk4_settings() {
  theme_desktop_write_gtk_settings "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini" "$@"
}

theme_desktop_write_gtk3_css() {
  local gtk3_css="${XDG_CONFIG_HOME}/gtk-3.0/gtk.css"

  theme_desktop_write_generated_file "${gtk3_css}" <<'EOF'
/* Generated by hypr theme desktop sync.
 * Loaded after the active GTK theme. Do not set palette colors here; the
 * selected GTK theme owns application surfaces and selection colors.
 */
.background.csd {
  border-radius: 0px;
}
EOF
}

# libadwaita ignores gtk-theme-name; its only override hook is the user's
# ~/.config/gtk-4.0/gtk.css. Import the resolved theme's GTK4 CSS so palette
# variables (@theme_bg_color, @theme_fg_color, …) reach libadwaita widgets.
theme_desktop_write_gtk4_css() {
  local gtk4_css="${XDG_CONFIG_HOME}/gtk-4.0/gtk.css"
  local theme_gtk4_css=""

  case "${RESOLVED_GTK_THEME}" in
    Pywal16-Gtk)
      theme_gtk4_css="${XDG_DATA_HOME:-$HOME/.local/share}/themes/Pywal16-Gtk/gtk-4.0/gtk.css"
      ;;
    Adwaita|"")
      :
      ;;
    *)
      if [[ -f "${HOME}/.themes/${RESOLVED_GTK_THEME}/gtk-4.0/gtk.css" ]]; then
        theme_gtk4_css="${HOME}/.themes/${RESOLVED_GTK_THEME}/gtk-4.0/gtk.css"
      elif [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/themes/${RESOLVED_GTK_THEME}/gtk-4.0/gtk.css" ]]; then
        theme_gtk4_css="${XDG_DATA_HOME:-$HOME/.local/share}/themes/${RESOLVED_GTK_THEME}/gtk-4.0/gtk.css"
      fi
      ;;
  esac

  mkdir -p "${XDG_CONFIG_HOME}/gtk-4.0"
  if [[ -n "${theme_gtk4_css}" && -f "${theme_gtk4_css}" ]]; then
    theme_desktop_write_generated_file "${gtk4_css}" <<EOF
/* Generated by hypr theme desktop sync.
 * libadwaita ignores gtk-theme-name; this @import is the only override hook.
 */
@import url("file://${theme_gtk4_css}");

.background.csd {
  border-radius: 0px;
}
EOF
  else
    theme_desktop_write_generated_file "${gtk4_css}" <<'EOF'
/* Generated by hypr theme desktop sync.
 * No active GTK4 theme to import. libadwaita uses its built-in style.
 */
.background.csd {
  border-radius: 0px;
}
EOF
  fi
}

theme_desktop_configure_gtk() {
  local gtk3_font=""
  local gtk3_font_size=""
  local gtkrc_file="${HOME}/.gtkrc-2.0"
  local xsettingsd_file="${XDG_CONFIG_HOME}/xsettingsd/xsettingsd.conf"
  local prefer_dark=0

  gtk3_font="${GTK3_FONT:-${FONT}}"
  gtk3_font_size="${GTK3_FONT_SIZE:-${FONT_SIZE}}"
  [[ "${COLOR_SCHEME}" == "prefer-dark" ]] && prefer_dark=1

  mkdir -p "${XDG_CONFIG_HOME}/gtk-3.0" "${XDG_CONFIG_HOME}/xsettingsd" || return 1
  theme_desktop_write_gtk3_css || return 1
  theme_desktop_write_generated_file "${gtkrc_file}" <<EOF || return 1
# Generated by hypr theme desktop sync.
include "${HOME}/.gtkrc-2.0.mime"
gtk-theme-name="${RESOLVED_GTK_THEME}"
gtk-icon-theme-name="${ICON_THEME}"
gtk-font-name="${gtk3_font} ${gtk3_font_size}"
gtk-cursor-theme-name="${CURSOR_THEME}"
gtk-cursor-theme-size=${CURSOR_SIZE}
gtk-application-prefer-dark-theme=${prefer_dark}
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle="hintfull"
gtk-xft-rgba="rgb"
EOF

  theme_desktop_write_gtk_settings "${XDG_CONFIG_HOME}/gtk-3.0/settings.ini" \
    "${prefer_dark}" "${gtk3_font}" "${gtk3_font_size}" || return 1

  theme_desktop_write_gtk4_settings "${prefer_dark}" "${gtk3_font}" "${gtk3_font_size}" || return 1
  theme_desktop_write_gtk4_css || return 1

  if command -v flatpak >/dev/null 2>&1; then
    flatpak \
      --user override \
      --filesystem="${HOME}/.icons" \
      --filesystem="${XDG_DATA_HOME:-$HOME/.local/share}/icons" \
      --env=GTK_THEME="${RESOLVED_GTK_THEME}" \
      --env=ICON_THEME="${ICON_THEME}" ||
      print_log -sec "theme" -warn flatpak "override failed"
  fi

  theme_desktop_write_generated_file "${xsettingsd_file}" <<EOF
# Generated by hypr theme desktop sync.
Net/ThemeName "${RESOLVED_GTK_THEME}"
Net/IconThemeName "${ICON_THEME}"
Gtk/CursorThemeName "${CURSOR_THEME}"
Gtk/CursorThemeSize ${CURSOR_SIZE}
Gtk/FontName "${gtk3_font} ${gtk3_font_size}"
Gtk/ApplicationPreferDarkTheme ${prefer_dark}
Net/EnableEventSounds 1
Net/EnableInputFeedbackSounds 0
Xft/Antialias 1
Xft/Hinting 1
Xft/HintStyle "hintfull"
Xft/RGBA "rgb"
EOF
}

theme_desktop_configure_xcursor_resources() {
  theme_desktop_update_xcursor_resource "${HOME}/.Xresources" true || return 1
  theme_desktop_update_xcursor_resource "${HOME}/.Xdefaults"
}

theme_desktop_dconf_payload() {
  cat <<EOF
[org/gnome/desktop/interface]
icon-theme='${ICON_THEME}'
gtk-theme='${RESOLVED_GTK_THEME}'
color-scheme='${COLOR_SCHEME}'
cursor-theme='${CURSOR_THEME}'
cursor-size=${CURSOR_SIZE}
font-name='${FONT} ${FONT_SIZE}'
document-font-name='${DOCUMENT_FONT} ${DOCUMENT_FONT_SIZE}'
monospace-font-name='${MONOSPACE_FONT} ${MONOSPACE_FONT_SIZE}'
font-antialiasing='${FONT_ANTIALIASING}'
EOF

  # dconf load does not validate against the schema, so an empty FONT_HINTING
  # would be stored as '', outside the key's enum, and GSettings then silently
  # serves the schema default instead.
  [[ -n "${FONT_HINTING:-}" ]] && printf "font-hinting='%s'\n" "${FONT_HINTING}"

  cat <<EOF

[org/cinnamon/desktop/interface]
icon-theme='${ICON_THEME}'
gtk-theme='${RESOLVED_GTK_THEME}'
cursor-theme='${CURSOR_THEME}'
cursor-size=${CURSOR_SIZE}
font-name='${FONT} ${FONT_SIZE}'

[org/gnome/desktop/default-applications/terminal]
exec='$(command -v "${TERMINAL}")'

[org/gnome/desktop/wm/preferences]
button-layout='${BUTTON_LAYOUT}'
EOF
}

theme_desktop_write_dconf_content() {
  local dconf_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/dconf"
  local dconf_tmp=""

  mkdir -p "$(dirname "${dconf_file}")"
  dconf_tmp="$(mktemp "${dconf_file}.tmp.XXXXXX")" || return 1
  theme_desktop_dconf_payload >"${dconf_tmp}" || {
    rm -f "${dconf_tmp}"
    return 1
  }
  if [[ -f "${dconf_file}" ]] && cmp -s "${dconf_tmp}" "${dconf_file}"; then
    rm -f "${dconf_tmp}"
    print_log -sec "dconf" -stat "skip" "unchanged"
    return 0
  fi

  if dconf load -f / <"${dconf_tmp}" >/dev/null 2>&1; then
    mv -f "${dconf_tmp}" "${dconf_file}"
    print_log -sec "dconf" -stat "loaded" "${dconf_file}"
  else
    rm -f "${dconf_tmp}"
    print_log -sec "dconf" -warn "failed" "${dconf_file}"
    return 1
  fi
}

theme_desktop_restart_portal_backends_if_needed() {
  local portal_reset_script="${LIB_DIR}/hypr/system/reset-xdg-portal.sh"
  local dconf_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/dconf"
  local current_hash="" synced_hash=""

  [[ -x "${portal_reset_script}" ]] || return 0
  current_hash="$(md5sum "${dconf_file}" 2>/dev/null || true)"
  current_hash="${current_hash%% *}"
  [[ -n "${current_hash}" ]] || return 0
  synced_hash="$(state_get "portal_dconf_hash" "" 2>/dev/null || true)"
  [[ "${current_hash}" == "${synced_hash}" ]] && return 0

  if "${portal_reset_script}" >/dev/null 2>&1; then
    state_set "portal_dconf_hash" "${current_hash}" "staterc" 2>/dev/null || true
    print_log -sec "dconf" -stat "portal" "restarted"
  else
    print_log -sec "dconf" -warn "portal" "restart failed"
  fi
}

theme_desktop_prepare_state() {
  theme_desktop_resolve_values
}

theme_desktop_static_state_hash() {
  local flatpak_installed=0
  local active_palette="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/active-palette.json"
  local pywal_colors="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json"
  local qtct_kde_colors="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/Pywal.colors"
  local qtct_qt6_colors="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/pywal16.conf"
  local shell_dir=""
  local source_file=""
  local source_hash=""
  local -a source_files=(
    "${BASH_SOURCE[0]}"
    "${LIB_DIR}/hypr/render/_shell.py"
    "${LIB_DIR}/hypr/render/_roles.py"
    "${LIB_DIR}/hypr/theme/lib/install_kvantum_theme.py"
  )

  command -v flatpak >/dev/null 2>&1 && flatpak_installed=1
  shell_dir="$(theme_desktop_kvantum_shell_dir)"
  for source_file in "${active_palette}" "${pywal_colors}" "${qtct_kde_colors}" \
    "${qtct_qt6_colors}" "${shell_dir}/shell.svg" "${shell_dir}/shell.kvconfig" "${shell_dir}/shell.map"; do
    [[ -f "${source_file}" ]] && source_files+=("${source_file}")
  done
  source_hash="$(hypr_hash_cache_digest_files "${source_files[@]}")" || return 1

  hypr_hash_cache_digest_strings \
    "source_hash=${source_hash}" \
    "gtk_theme=${RESOLVED_GTK_THEME}" \
    "icon_theme=${ICON_THEME}" \
    "cursor_theme=${CURSOR_THEME}" \
    "cursor_size=${CURSOR_SIZE}" \
    "terminal=${TERMINAL}" \
    "font=${FONT}" \
    "font_size=${FONT_SIZE}" \
    "document_font=${DOCUMENT_FONT}" \
    "document_font_size=${DOCUMENT_FONT_SIZE}" \
    "monospace_font=${MONOSPACE_FONT}" \
    "monospace_font_size=${MONOSPACE_FONT_SIZE}" \
    "button_layout=${BUTTON_LAYOUT}" \
    "font_antialiasing=${FONT_ANTIALIASING}" \
    "font_hinting=${FONT_HINTING}" \
    "kvantum_theme=${RESOLVED_KVANTUM_THEME}" \
    "kde_color_scheme=${RESOLVED_KDE_COLOR_SCHEME}" \
    "kde_widget_style=${RESOLVED_KDE_WIDGET_STYLE:-kvantum}" \
    "flatpak_installed=${flatpak_installed}"
}

theme_desktop_static_targets_ready() {
  local required_target=""
  local kvantum_theme=""
  local -a required_targets=(
    "${XDG_CONFIG_HOME}/Kvantum/kvantum.kvconfig"
    "${XDG_CONFIG_HOME}/qt6ct/qt6ct.conf"
    "${XDG_CONFIG_HOME}/qt6ct/colors/pywal16.conf"
    "${XDG_CONFIG_HOME}/kdeglobals"
    "${XDG_CONFIG_HOME}/kdedefaults/kdeglobals"
    "${XDG_DATA_HOME}/icons/default/index.theme"
    "${HOME}/.icons/default/index.theme"
    "${HOME}/.gtkrc-2.0"
    "${XDG_CONFIG_HOME}/gtk-3.0/gtk.css"
    "${XDG_CONFIG_HOME}/gtk-3.0/settings.ini"
    "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini"
    "${XDG_CONFIG_HOME}/gtk-4.0/gtk.css"
    "${XDG_CONFIG_HOME}/xsettingsd/xsettingsd.conf"
    "${HOME}/.Xresources"
  )

  if [[ "${RESOLVED_KDE_COLOR_SCHEME:-}" == "Pywal" ]]; then
    required_targets+=("${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/Pywal.colors")
  fi

  kvantum_theme="$(theme_desktop_kvantum_output_theme_name)"
  required_targets+=(
    "${XDG_CONFIG_HOME}/Kvantum/${kvantum_theme}/${kvantum_theme}.svg"
    "${XDG_CONFIG_HOME}/Kvantum/${kvantum_theme}/${kvantum_theme}.kvconfig"
  )

  for required_target in "${required_targets[@]}"; do
    [[ -e "${required_target}" ]] || return 1
  done
}

theme_desktop_apply_runtime_resolved() {
  theme_desktop_export_cursor_environment
  theme_desktop_export_session_qt_env
  theme_desktop_write_dconf_content || return 1
  theme_desktop_restart_portal_backends_if_needed
  if [[ "${THEME_DESKTOP_SYNC_LOG_DCONF:-1}" -eq 1 ]]; then
    print_log -sec "dconf" -stat "Loaded dconf settings" "::"
    print_log -y "#-----------------------------------------------#"
    theme_desktop_dconf_payload
    print_log -y "#-----------------------------------------------#"
  fi
  return 0
}

theme_desktop_apply_static_resolved() {
  theme_desktop_install_kvantum_theme || return 1
  theme_desktop_install_kde_color_scheme || return 1
  theme_desktop_install_qtct_color_scheme || return 1
  theme_desktop_configure_qt_kde_bridge || return 1
  theme_desktop_ini_write_batch "${XDG_DATA_HOME}/icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}" || return 1
  theme_desktop_ini_write_batch "${HOME}/.icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}" || return 1
  theme_desktop_configure_gtk || return 1
  theme_desktop_configure_xcursor_resources
}

theme_desktop_apply_static_resolved_if_needed() {
  local static_hash=""
  local hash_file=""

  hash_file="$(hypr_hash_cache_runtime_file "theme-desktop-static.hash")" || return 1
  static_hash="$(theme_desktop_static_state_hash)" || return 1

  # hypr_hash_cache_is_current honors FORCE_COLOR_REGEN; store honors
  # HYPR_WAL_CACHE_ENABLE — no per-callsite flag checks needed.
  if theme_desktop_static_targets_ready \
    && hypr_hash_cache_is_current "${hash_file}" "${static_hash}"; then
    print_log -sec "theme" -stat "skip" "static desktop sync unchanged"
    return 0
  fi

  theme_desktop_apply_static_resolved || return 1
  hypr_hash_cache_store "${hash_file}" "${static_hash}" || return 1
}

theme_desktop_sync_runtime() {
  theme_desktop_prepare_state || return 1
  theme_desktop_apply_runtime_resolved || return 1
  theme_desktop_set_cursor_async
}

theme_desktop_sync_static() {
  theme_desktop_prepare_state || return 1
  theme_desktop_apply_static_resolved_if_needed
}

theme_desktop_sync_full() {
  theme_desktop_prepare_state || return 1
  theme_desktop_apply_static_resolved_if_needed || return 1
  theme_desktop_apply_runtime_resolved || return 1
  theme_desktop_apply_cursor_theme
}
