#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Shared desktop-theme sync helpers.
#
# This library is the single owner for desktop-facing theme writes:
#   - GTK, cursor resource files
#   - GNOME dconf theme state
#   - portal restarts after GTK/dconf changes
#
# Callers should source runtime/init.bash and load state/system modules first.

if ! declare -F hypr_hash_cache_runtime_file >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${LIB_DIR:-$HOME/.local/lib}/hypr/core/hash-cache.sh" || return 1 2>/dev/null || exit 1
fi

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

theme_desktop_write_generated_file() {
  local target_file="$1"
  local target_dir=""
  local tmp_file=""

  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}" || return 1
  tmp_file="$(mktemp "${target_dir}/.$(basename "${target_file}").XXXXXX")" || return 1
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

theme_desktop_hyq_value() {
  local raw_value="${1-}"

  if [[ ${#raw_value} -ge 2 && "${raw_value:0:1}" == '"' && "${raw_value:${#raw_value}-1:1}" == '"' ]]; then
    raw_value="${raw_value:1:${#raw_value}-2}"
    raw_value="${raw_value//\\\"/\"}"
    raw_value="${raw_value//\\\$/\$}"
    raw_value="${raw_value//\\\`/\`}"
    raw_value="${raw_value//\\\\/\\}"
    printf '%s' "${raw_value}"
    return 0
  fi

  if [[ ${#raw_value} -ge 2 && "${raw_value:0:1}" == "'" && "${raw_value:${#raw_value}-1:1}" == "'" ]]; then
    printf '%s' "${raw_value:1:${#raw_value}-2}"
    return 0
  fi

  printf '%s' "${raw_value}"
}

theme_desktop_load_hyq_env() {
  local hyq_output="$1"
  local var_name=""
  local raw_value=""
  local value=""
  local line=""

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" =~ ^(__[A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    var_name="${BASH_REMATCH[1]}"
    raw_value="${BASH_REMATCH[2]}"

    case "${var_name}" in
      __ICON_THEME | __COLOR_SCHEME | __CURSOR_THEME | __CURSOR_SIZE | \
      __TERMINAL | __FONT | __FONT_SIZE | __FONT_STYLE | __DOCUMENT_FONT | \
      __DOCUMENT_FONT_SIZE | __MONOSPACE_FONT | __MONOSPACE_FONT_SIZE | \
      __BUTTON_LAYOUT | __FONT_ANTIALIASING | __FONT_HINTING)
        ;;
      *)
        continue
        ;;
    esac

    value="$(theme_desktop_hyq_value "${raw_value}")"
    printf -v "${var_name}" '%s' "${value}"
  done <<<"${hyq_output}"
}

theme_desktop_load_config_values() {
  local theme_conf="${HYPR_THEME_METADATA_FILE:-${HYPR_CONFIG_HOME}/themes/theme.conf}"
  local theme_hyq_output=""
  local query_output=""
  local -a hyq_args=(
    "${HYPRLAND_CONFIG}"
    --source
    --export env
    --allow-missing
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
  )

  unset __ICON_THEME __COLOR_SCHEME __CURSOR_THEME __CURSOR_SIZE \
    __TERMINAL __FONT __FONT_SIZE __FONT_STYLE __DOCUMENT_FONT \
    __DOCUMENT_FONT_SIZE __MONOSPACE_FONT __MONOSPACE_FONT_SIZE \
    __BUTTON_LAYOUT __FONT_ANTIALIASING __FONT_HINTING

  [[ -r "${HYPRLAND_CONFIG}" ]] || return 0
  command -v hyq >/dev/null 2>&1 || return 0

  if [[ "${selected_color_mode:-1}" -eq 0 ]] && [[ -r "${theme_conf}" ]]; then
    # Manual color mode uses theme.conf for icon/cursor instead of env overrides.
    theme_hyq_output="$(
      hyq "${theme_conf}" --export env --allow-missing \
        -Q '$ICON_THEME[string]' \
        -Q '$CURSOR_THEME[string]' \
        -Q '$CURSOR_SIZE'
    )"
    theme_desktop_load_hyq_env "${theme_hyq_output}"
    ICON_THEME="${__ICON_THEME:-${ICON_THEME:-}}"
    CURSOR_THEME="${__CURSOR_THEME:-${CURSOR_THEME:-}}"
    CURSOR_SIZE="${__CURSOR_SIZE:-${CURSOR_SIZE:-}}"
  else
    hyq_args+=(
      -Q '$ICON_THEME[string]'
      -Q '$CURSOR_THEME[string]'
      -Q '$CURSOR_SIZE'
    )
  fi

  query_output="$(hyq "${hyq_args[@]}")"
  theme_desktop_load_hyq_env "${query_output}"

  COLOR_SCHEME="${__COLOR_SCHEME:-${COLOR_SCHEME:-}}"
  ICON_THEME="${__ICON_THEME:-${ICON_THEME:-}}"
  CURSOR_THEME="${__CURSOR_THEME:-${CURSOR_THEME:-}}"
  CURSOR_SIZE="${__CURSOR_SIZE:-${CURSOR_SIZE:-}}"
  TERMINAL="${__TERMINAL:-${TERMINAL:-}}"
  FONT="${__FONT:-${FONT:-}}"
  FONT_SIZE="${__FONT_SIZE:-${FONT_SIZE:-}}"
  FONT_STYLE="${__FONT_STYLE:-${FONT_STYLE:-}}"
  DOCUMENT_FONT="${__DOCUMENT_FONT:-${DOCUMENT_FONT:-}}"
  DOCUMENT_FONT_SIZE="${__DOCUMENT_FONT_SIZE:-${DOCUMENT_FONT_SIZE:-}}"
  MONOSPACE_FONT="${__MONOSPACE_FONT:-${MONOSPACE_FONT:-}}"
  MONOSPACE_FONT_SIZE="${__MONOSPACE_FONT_SIZE:-${MONOSPACE_FONT_SIZE:-}}"
  BUTTON_LAYOUT="${__BUTTON_LAYOUT:-${BUTTON_LAYOUT:-}}"
  FONT_ANTIALIASING="${__FONT_ANTIALIASING:-${FONT_ANTIALIASING:-}}"
  FONT_HINTING="${__FONT_HINTING:-${FONT_HINTING:-}}"
}

theme_desktop_resolve_values() {
  local env_theme_file="${HYPR_CONFIG_HOME}/env-theme"
  local color_variant=""
  local layer_var=""
  local layer_value=""
  local -a layered_vars=(
    ICON_THEME
    CURSOR_THEME
    CURSOR_SIZE
    TERMINAL
    FONT
    FONT_SIZE
    FONT_STYLE
    DOCUMENT_FONT
    DOCUMENT_FONT_SIZE
    MONOSPACE_FONT
    MONOSPACE_FONT_SIZE
    BUTTON_LAYOUT
    FONT_ANTIALIASING
    FONT_HINTING
  )

  if [[ -d /run/current-system/sw/share/themes ]]; then
    THEMES_DIR=/run/current-system/sw/share/themes
    export THEMES_DIR
  fi

  # shellcheck source=/dev/null
  [[ -f "${env_theme_file}" ]] && source "${env_theme_file}"

  HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr/hyprland.conf}"
  color_variant="$(state_get_color_variant 2>/dev/null || true)"
  resolved_color_variant="${resolved_color_variant:-${color_variant:-dark}}"

  case "${selected_color_mode:-}" in
    0 | 1 | 2 | 3) ;;
    *) selected_color_mode=0 ;;
  esac

  COLOR_SCHEME="prefer-${resolved_color_variant}"
  FONT="${FONT:-Cantarell}"
  FONT_SIZE="${FONT_SIZE:-10}"
  DOCUMENT_FONT="${DOCUMENT_FONT:-Cantarell}"
  DOCUMENT_FONT_SIZE="${DOCUMENT_FONT_SIZE:-10}"
  MONOSPACE_FONT="${MONOSPACE_FONT:-JetBrainsMono Nerd Font}"
  MONOSPACE_FONT_SIZE="${MONOSPACE_FONT_SIZE:-9}"
  FONT_ANTIALIASING="${FONT_ANTIALIASING:-rgba}"
  FONT_HINTING="${FONT_HINTING:-}"
  theme_desktop_load_config_values

  for layer_var in "${layered_vars[@]}"; do
    [[ -n "${!layer_var-}" ]] && continue
    layer_value="$(hypr_config_value_from_layers "${layer_var}" 2>/dev/null || true)"
    [[ -n "${layer_value}" ]] && printf -v "${layer_var}" '%s' "${layer_value}"
  done

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

  if [[ "${COLOR_SCHEME}" == "prefer-light" ]]; then
    RESOLVED_GTK_THEME="${resolved_gtk}"
    RESOLVED_KVANTUM_THEME="KvGnome"
    RESOLVED_KDE_COLOR_SCHEME="KvGnome"
  else
    RESOLVED_GTK_THEME="${resolved_gtk}"
    RESOLVED_KVANTUM_THEME="KvGnomeDark"
    RESOLVED_KDE_COLOR_SCHEME="KvGnomeDark"
  fi

  RESOLVED_KDE_WIDGET_STYLE="kvantum"
  # In theme mode, prefer the generated pywal16 Kvantum theme when the
  # active pack ships kvconfig.theme and kvantum.theme.
  # This keeps Qt widgets on the active palette instead of the hardcoded
  # KvGnome[Dark] fallback.
  RESOLVED_KVANTUM_THEME_IS_PACK=0
  if [[ "${selected_color_mode:-0}" -eq 0 ]] && theme_desktop_pack_has_kvantum_theme; then
    RESOLVED_KVANTUM_THEME="$(theme_desktop_kvantum_output_theme_name)"
    RESOLVED_KVANTUM_THEME_IS_PACK=1
  fi

  # Prefer the pywal-driven KDE color scheme whenever wal.qtct.sh has
  # emitted Pywal.colors — this is what makes Dolphin's selection and
  # other KColorScheme-driven widgets follow the active palette in both
  # theme and wallpaper modes. Force widgetStyle=Fusion when we don't
  # have a per-theme Kvantum (otherwise Kvantum's hardcoded KvGnome[Dark]
  # palette paints over QPalette). When a pack-backed Kvantum theme is
  # deployed, keep widgetStyle=kvantum so widget art stays theme-coherent;
  # KColorScheme-driven bits still honor Pywal in parallel.
  # Delete ${XDG_DATA_HOME}/color-schemes/Pywal.colors to fall back to
  # the theme-pack-supplied KDE scheme.
  if [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/Pywal.colors" ]]; then
    RESOLVED_KDE_COLOR_SCHEME="Pywal"
    if [[ "${selected_color_mode:-0}" -ne 0 ]]; then
      RESOLVED_KVANTUM_THEME="$(theme_desktop_kvantum_output_theme_name)"
    fi
    if [[ "${RESOLVED_KVANTUM_THEME_IS_PACK:-0}" -ne 1 \
      && "${RESOLVED_KVANTUM_THEME}" != "$(theme_desktop_kvantum_output_theme_name)" ]]; then
      RESOLVED_KDE_WIDGET_STYLE="Fusion"
    fi
  fi

  export ICON_THEME COLOR_SCHEME CURSOR_THEME CURSOR_SIZE TERMINAL \
    FONT FONT_SIZE FONT_STYLE DOCUMENT_FONT DOCUMENT_FONT_SIZE MONOSPACE_FONT \
    MONOSPACE_FONT_SIZE BUTTON_LAYOUT FONT_ANTIALIASING FONT_HINTING \
    RESOLVED_KVANTUM_THEME RESOLVED_KDE_COLOR_SCHEME RESOLVED_KDE_WIDGET_STYLE
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

theme_desktop_pack_has_kvantum_theme() {
  local pack_dir="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME:-}"
  [[ -n "${HYPR_THEME:-}" ]] || return 1
  [[ -f "${pack_dir}/kvantum/kvconfig.theme" ]] || return 1
  [[ -f "${pack_dir}/kvantum/kvantum.theme" ]] || return 1
}

theme_desktop_kvantum_pack_theme_name() {
  local safe_name="${HYPR_THEME:-hypr-theme}"

  safe_name="${safe_name//[[:space:]]/_}"
  safe_name="${safe_name//\#/_}"
  safe_name="${safe_name//\//_}"
  while [[ "${safe_name}" == *"__"* ]]; do
    safe_name="${safe_name//__/_}"
  done
  safe_name="${safe_name##_}"
  safe_name="${safe_name%%_}"
  printf '%s' "${safe_name:-hypr-theme}"
}

theme_desktop_kvantum_output_theme_name() {
  printf '%s' "pywal16"
}

theme_desktop_kvantum_svg_source_path() {
  local pack_dir="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME:-}"

  [[ -n "${HYPR_THEME:-}" && -f "${pack_dir}/kvantum/kvantum.theme" ]] || return 1
  printf '%s\n' "${pack_dir}/kvantum/kvantum.theme"
}

theme_desktop_kvantum_pack_source_hash() {
  local pack_dir="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME:-}"
  local completion="${LIB_DIR}/hypr/theme/complete-kvantum-themes.sh"
  local kvantum_svg_source=""
  local -a input_files=()

  theme_desktop_pack_has_kvantum_theme || {
    printf ''
    return 0
  }

  kvantum_svg_source="$(theme_desktop_kvantum_svg_source_path)" || return 1

  input_files+=(
    "${kvantum_svg_source}"
    "${pack_dir}/kvantum/kvconfig.theme"
  )

  [[ -f "${pack_dir}/kvantum/colors.map" ]] && input_files+=("${pack_dir}/kvantum/colors.map")
  [[ -f "${completion}" ]] && input_files+=("${completion}")

  hypr_hash_cache_digest_files "${input_files[@]}"
}

theme_desktop_apply_kvantum_color_map() {
  local colors_map="$1"
  shift

  local colors_shell="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors-shell.sh"
  local hex_color=""
  local pywal_var=""
  local pywal_value=""
  local -a sed_args=()

  [[ -f "${colors_map}" && -f "${colors_shell}" ]] || return 0
  # shellcheck source=/dev/null
  source "${colors_shell}" || return 1

  while IFS='=' read -r hex_color pywal_var || [[ -n "${hex_color}" ]]; do
    [[ "${hex_color}" =~ ^#.*$ && ! "${hex_color}" =~ ^#[0-9A-Fa-f]{6}$ ]] && continue
    [[ -n "${hex_color}" && -n "${pywal_var}" ]] || continue

    pywal_value="${!pywal_var-}"
    [[ -n "${pywal_value}" ]] || continue
    pywal_value="$(sed_escape_replacement "${pywal_value}")"
    sed_args+=(-e "s|${hex_color}|${pywal_value}|gi")
  done <"${colors_map}"

  ((${#sed_args[@]} > 0)) || return 0
  sed -i "${sed_args[@]}" "$@"
}

# Deploy the active theme pack's Kvantum SVG plus config into
# fixed-name Kvantum layout: ${XDG_CONFIG_HOME}/Kvantum/pywal16/pywal16.{svg,kvconfig}.
# Source files in the pack use `.theme` extensions; Kvantum needs them
# renamed at install time. No-op if the pack ships no kvantum subtree.
#
# Pipeline:
#   1. Run completion (idempotent) for the active theme.
#   2. Copy SVG and kvconfig from the active theme into Kvantum's install dir.
#   3. In wallpaper/pywal recolor modes, rewrite the installed files using
#      colors.map → live pywal palette. In theme mode, leave the theme's
#      Kvantum files intact.
theme_desktop_install_pack_kvantum_theme() {
  theme_desktop_pack_has_kvantum_theme || return 0

  local pack_dir="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  local kvantum_theme=""
  local dest_dir=""
  local completion="${LIB_DIR}/hypr/theme/complete-kvantum-themes.sh"
  local colors_map="${pack_dir}/kvantum/colors.map"
  local kvantum_svg_source=""

  kvantum_theme="$(theme_desktop_kvantum_output_theme_name)"
  dest_dir="${XDG_CONFIG_HOME}/Kvantum/${kvantum_theme}"
  kvantum_svg_source="$(theme_desktop_kvantum_svg_source_path)" || return 1

  if [[ -f "${completion}" ]]; then
    bash "${completion}" "${HYPR_THEME}" >/dev/null 2>&1 || true
  fi

  mkdir -p "${dest_dir}" || return 1
  cp -f "${kvantum_svg_source}" "${dest_dir}/${kvantum_theme}.svg" || return 1
  cp -f "${pack_dir}/kvantum/kvconfig.theme" "${dest_dir}/${kvantum_theme}.kvconfig" || return 1

  if [[ "${selected_color_mode:-0}" -ne 0 ]]; then
    theme_desktop_apply_kvantum_color_map \
      "${colors_map}" \
      "${dest_dir}/${kvantum_theme}.svg" \
      "${dest_dir}/${kvantum_theme}.kvconfig" || return 1
  fi
}

theme_desktop_configure_qt_kde_bridge() {
  theme_desktop_write_generated_file "${XDG_CONFIG_HOME}/Kvantum/kvantum.kvconfig" <<EOF
[General]
theme=${RESOLVED_KVANTUM_THEME}
EOF

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/kdeglobals" \
    "General:ColorScheme=${RESOLVED_KDE_COLOR_SCHEME}" \
    "Icons:Theme=${ICON_THEME}" \
    "KDE:widgetStyle=${RESOLVED_KDE_WIDGET_STYLE:-kvantum}" \
    "UiSettings:ColorScheme=${RESOLVED_KDE_COLOR_SCHEME}"

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/kdedefaults/kdeglobals" \
    "General:ColorScheme=${RESOLVED_KDE_COLOR_SCHEME}" \
    "Icons:Theme=${ICON_THEME}" \
    "KDE:widgetStyle=${RESOLVED_KDE_WIDGET_STYLE:-kvantum}"
}

theme_desktop_write_gtk4_settings() {
  local prefer_dark="$1"
  local gtk3_font="$2"
  local gtk3_font_size="$3"
  mkdir -p "${XDG_CONFIG_HOME}/gtk-4.0"
  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini" \
    "Settings:gtk-theme-name=${RESOLVED_GTK_THEME}" \
    "Settings:gtk-icon-theme-name=${ICON_THEME}" \
    "Settings:gtk-cursor-theme-name=${CURSOR_THEME}" \
    "Settings:gtk-cursor-theme-size=${CURSOR_SIZE}" \
    "Settings:gtk-font-name=${gtk3_font} ${gtk3_font_size}" \
    "Settings:gtk-application-prefer-dark-theme=${prefer_dark}"
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

  mkdir -p "${XDG_CONFIG_HOME}/gtk-3.0" "${XDG_CONFIG_HOME}/xsettingsd"
  theme_desktop_write_gtk3_css || return 1
  theme_desktop_write_generated_file "${gtkrc_file}" <<EOF
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

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/gtk-3.0/settings.ini" \
    "Settings:gtk-theme-name=${RESOLVED_GTK_THEME}" \
    "Settings:gtk-icon-theme-name=${ICON_THEME}" \
    "Settings:gtk-cursor-theme-name=${CURSOR_THEME}" \
    "Settings:gtk-cursor-theme-size=${CURSOR_SIZE}" \
    "Settings:gtk-font-name=${gtk3_font} ${gtk3_font_size}" \
    "Settings:gtk-application-prefer-dark-theme=${prefer_dark}"

  theme_desktop_write_gtk4_settings "${prefer_dark}" "${gtk3_font}" "${gtk3_font_size}" || return 1
  theme_desktop_write_gtk4_css || return 1

  if pkg_installed flatpak; then
    flatpak \
      --user override \
      --filesystem="${HOME}/.icons" \
      --filesystem="${XDG_DATA_HOME:-$HOME/.local/share}/icons" \
      --env=GTK_THEME="${RESOLVED_GTK_THEME}" \
      --env=ICON_THEME="${ICON_THEME}"
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 &
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
  theme_desktop_update_xcursor_resource "${HOME}/.Xresources" true
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
font-hinting='${FONT_HINTING}'

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
    return 1
  fi
}

theme_desktop_restart_portal_backends_if_needed() {
  local portal_reset_script="${LIB_DIR}/hypr/system/reset-xdg-portal.sh"

  [[ "${theme_desktop_dconf_content_changed:-0}" -eq 1 ]] || return 0
  [[ -x "${portal_reset_script}" ]] || return 0

  if "${portal_reset_script}" >/dev/null 2>&1; then
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
  local kvantum_pack_hash=""
  local pipeline_hash=""
  local pywal_colors="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json"
  local pywal_hash=""
  local -a pipeline_files=(
    "${BASH_SOURCE[0]}"
  )

  pkg_installed flatpak && flatpak_installed=1
  pipeline_hash="$(hypr_hash_cache_digest_files "${pipeline_files[@]}")"
  [[ -f "${pywal_colors}" ]] && pywal_hash="$(hypr_hash_cache_digest_files "${pywal_colors}")"
  if [[ "${RESOLVED_KVANTUM_THEME_IS_PACK:-0}" -eq 1 ]]; then
    kvantum_pack_hash="$(theme_desktop_kvantum_pack_source_hash)"
  fi

  hypr_hash_cache_digest_strings \
    "pipeline_hash=${pipeline_hash}" \
    "gtk_theme=${RESOLVED_GTK_THEME}" \
    "icon_theme=${ICON_THEME}" \
    "cursor_theme=${CURSOR_THEME}" \
    "cursor_size=${CURSOR_SIZE}" \
    "terminal=${TERMINAL}" \
    "font=${FONT}" \
    "font_size=${FONT_SIZE}" \
    "font_style=${FONT_STYLE}" \
    "document_font=${DOCUMENT_FONT}" \
    "document_font_size=${DOCUMENT_FONT_SIZE}" \
    "monospace_font=${MONOSPACE_FONT}" \
    "monospace_font_size=${MONOSPACE_FONT_SIZE}" \
    "button_layout=${BUTTON_LAYOUT}" \
    "font_antialiasing=${FONT_ANTIALIASING}" \
    "font_hinting=${FONT_HINTING}" \
    "kvantum_theme=${RESOLVED_KVANTUM_THEME}" \
    "kvantum_pack_hash=${kvantum_pack_hash}" \
    "kde_color_scheme=${RESOLVED_KDE_COLOR_SCHEME}" \
    "kde_widget_style=${RESOLVED_KDE_WIDGET_STYLE:-kvantum}" \
    "pywal_colors=${pywal_hash}" \
    "flatpak_installed=${flatpak_installed}"
}

theme_desktop_static_targets_ready() {
  local required_target=""
  local kvantum_pack_theme=""
  local -a required_targets=(
    "${XDG_CONFIG_HOME}/Kvantum/kvantum.kvconfig"
    "${XDG_CONFIG_HOME}/kdeglobals"
    "${XDG_CONFIG_HOME}/kdedefaults/kdeglobals"
    "${XDG_DATA_HOME}/icons/default/index.theme"
    "${HOME}/.icons/default/index.theme"
    "${HOME}/.gtkrc-2.0"
    "${XDG_CONFIG_HOME}/gtk-3.0/gtk.css"
    "${XDG_CONFIG_HOME}/gtk-3.0/settings.ini"
    "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini"
    "${XDG_CONFIG_HOME}/xsettingsd/xsettingsd.conf"
    "${HOME}/.Xresources"
  )

  if [[ "${RESOLVED_KVANTUM_THEME_IS_PACK:-0}" -eq 1 ]] && theme_desktop_pack_has_kvantum_theme; then
    kvantum_pack_theme="$(theme_desktop_kvantum_output_theme_name)"
    required_targets+=(
      "${XDG_CONFIG_HOME}/Kvantum/${kvantum_pack_theme}/${kvantum_pack_theme}.svg"
      "${XDG_CONFIG_HOME}/Kvantum/${kvantum_pack_theme}/${kvantum_pack_theme}.kvconfig"
    )
  fi

  for required_target in "${required_targets[@]}"; do
    [[ -e "${required_target}" ]] || return 1
  done
}

theme_desktop_apply_runtime_resolved() {
  theme_desktop_write_dconf_content
  theme_desktop_restart_portal_backends_if_needed
  if [[ "${THEME_DESKTOP_SYNC_LOG_DCONF:-1}" -eq 1 ]]; then
    print_log -sec "dconf" -stat "Loaded dconf settings" "::"
    print_log -y "#-----------------------------------------------#"
    theme_desktop_dconf_payload
    print_log -y "#-----------------------------------------------#"
  fi
}

theme_desktop_apply_static_resolved() {
  theme_desktop_install_pack_kvantum_theme
  theme_desktop_configure_qt_kde_bridge
  theme_desktop_ini_write_batch "${XDG_DATA_HOME}/icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}"
  theme_desktop_ini_write_batch "${HOME}/.icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}"
  theme_desktop_configure_gtk
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
  theme_desktop_prepare_state
  theme_desktop_apply_runtime_resolved
  theme_desktop_set_cursor_async
}

theme_desktop_sync_static() {
  theme_desktop_prepare_state
  theme_desktop_apply_static_resolved_if_needed
}

theme_desktop_sync_full() {
  theme_desktop_prepare_state
  theme_desktop_apply_static_resolved_if_needed
  theme_desktop_apply_runtime_resolved
  theme_desktop_apply_cursor_theme
}
