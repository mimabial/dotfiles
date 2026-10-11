#!/usr/bin/env bash

if ! declare -F hypr_hash_cache_runtime_file >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/hash-cache.bash" || return 1 2>/dev/null || exit 1
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
  } | ini_write_records "${config_file}"
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

source "${BASH_SOURCE[0]%/*}/desktop.settings.bash" || return 1

theme_desktop_sync_gtk_theme_links() {
  local -n desktop_settings_ref="$1"
  local pack_dir="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME:-}"

  if [[ -n "${HYPR_THEME:-}" && (-d "${pack_dir}/gtk-3.0" || -d "${pack_dir}/gtk-4.0") ]]; then
    mkdir -p "${HOME}/.themes"
    ln -snf "${pack_dir}" "${HOME}/.themes/${desktop_settings_ref[RESOLVED_GTK_THEME]}" || true
  fi
  [[ -d "${HOME}/.themes" ]] && find "${HOME}/.themes" -maxdepth 1 -lname "${HYPR_CONFIG_HOME}/themes/*" ! -name "${desktop_settings_ref[RESOLVED_GTK_THEME]}" -delete || true
}

theme_desktop_update_xcursor_resource() {
  local -n desktop_settings_ref="$1"
  shift
  local file="$1"
  local create="${2:-false}"

  if [[ ! -f "${file}" ]]; then
    [[ "${create}" == "true" ]] || return 0
    printf 'Xcursor.theme: %s\nXcursor.size: %s\n' "${desktop_settings_ref[CURSOR_THEME]}" "${desktop_settings_ref[CURSOR_SIZE]}" |
      theme_desktop_write_generated_file "${file}"
    return
  fi

  awk -v theme="${desktop_settings_ref[CURSOR_THEME]}" -v size="${desktop_settings_ref[CURSOR_SIZE]}" '
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
  local -n desktop_settings_ref="$1"
  local xcursor_path=""

  [[ -n "${desktop_settings_ref[CURSOR_THEME]}" && -n "${desktop_settings_ref[CURSOR_SIZE]}" ]] || return 0

  xcursor_path="${XCURSOR_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/icons:$HOME/.icons:/usr/share/icons}"
  export XCURSOR_THEME="${desktop_settings_ref[CURSOR_THEME]}"
  export XCURSOR_SIZE="${desktop_settings_ref[CURSOR_SIZE]}"
  export HYPRCURSOR_THEME="${desktop_settings_ref[CURSOR_THEME]}"
  export HYPRCURSOR_SIZE="${desktop_settings_ref[CURSOR_SIZE]}"
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
  local qt_env_file="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/qt-session.env"
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
  local -n desktop_settings_ref="$1"
  local dir=""
  local index=""

  for dir in "${XDG_DATA_HOME:-$HOME/.local/share}/icons" "${HOME}/.icons"; do
    index="${dir}/${desktop_settings_ref[CURSOR_THEME]}/index.theme"
    [[ -f "${index}" && -w "${index}" ]] || continue
    grep -qiE '^[[:space:]]*Inherits[[:space:]]*=[[:space:]]*"?default"?[[:space:]]*$' "${index}" || continue
    sed -i -E '/^[[:space:]]*Inherits[[:space:]]*=[[:space:]]*"?default"?[[:space:]]*$/d' "${index}"
    print_log -sec "theme" -stat "cursor" "removed Inherits=default cycle from ${index}"
  done
}

theme_desktop_apply_cursor_theme() {
  local -n desktop_settings_ref="$1"
  [[ -n "${desktop_settings_ref[CURSOR_THEME]}" && -n "${desktop_settings_ref[CURSOR_SIZE]}" ]] || return 0
  theme_desktop_resolve_instance_signature || return 0
  theme_desktop_sanitize_cursor_theme_index "${!desktop_settings_ref}"
  if ! HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE}" \
    hyprctl setcursor "${desktop_settings_ref[CURSOR_THEME]}" "${desktop_settings_ref[CURSOR_SIZE]}" >/dev/null 2>&1; then
    print_log -sec "theme" -warn "cursor" "failed to apply ${desktop_settings_ref[CURSOR_THEME]} (${desktop_settings_ref[CURSOR_SIZE]})"
  fi
}

theme_desktop_set_cursor_async() {
  local -n desktop_settings_ref="$1"
  [[ -n "${desktop_settings_ref[CURSOR_THEME]}" && -n "${desktop_settings_ref[CURSOR_SIZE]}" ]] || return 0
  theme_desktop_resolve_instance_signature || return 0
  theme_desktop_sanitize_cursor_theme_index "${!desktop_settings_ref}"
  HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE}" \
    hyprctl setcursor "${desktop_settings_ref[CURSOR_THEME]}" "${desktop_settings_ref[CURSOR_SIZE]}" >/dev/null 2>&1 &
}

theme_desktop_install_file() {
  local source_file="$1"
  local target_file="$2"
  [[ -f "${source_file}" ]] || return 0
  theme_desktop_write_generated_file "${target_file}" <"${source_file}"
}

theme_desktop_install_kde_color_scheme() {
  theme_desktop_install_file \
    "${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/Hypr.colors" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/Hypr.colors"
}

theme_desktop_install_kdeglobals_color_sections() {
  local target_file="$1"
  local source_file="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/Hypr.colors"
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

  printf '%s' "${records}" | ini_write_records "${target_file}" || return 1
}

theme_desktop_notify_kde_palette_changed() {
  command -v dbus-send >/dev/null 2>&1 || return 0
  dbus-send --session --type=signal \
    /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 \
    >/dev/null 2>&1 \
    || print_log -sec "theme" -warn "kde" "palette notification failed"
}

theme_desktop_notify_kde_fonts_changed() {
  command -v dbus-send >/dev/null 2>&1 || return 0
  dbus-send --session --type=signal \
    /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts \
    >/dev/null 2>&1 \
    || print_log -sec "theme" -warn "kde" "font notification failed"
}

theme_desktop_notify_kde_icons_changed() {
  local group=""

  command -v dbus-send >/dev/null 2>&1 || return 0
  for group in {0..5}; do
    dbus-send --session --type=signal \
      /KIconLoader org.kde.KIconLoader.iconChanged "int32:${group}" \
      >/dev/null 2>&1 \
      || print_log -sec "theme" -warn "kde" "icon notification failed for group ${group}"
  done
}

THEME_DESKTOP_TEXT_SIZE_BASE_PX=12
THEME_DESKTOP_UI_FONT_PT=10
THEME_DESKTOP_SMALL_FONT_PT=8

# Match Quickshell's px-to-point conversion.
theme_desktop_kde_font_entries() {
  local -n desktop_settings_ref="$1"
  shift
  local -n font_entries_ref="$1"
  local text_size="" ui_size="" small_size="" regular="-1,5,400,0,0,0,0,0,0,0,0,0,0,1"

  text_size="$(state_get TEXT_SIZE "${THEME_DESKTOP_TEXT_SIZE_BASE_PX}" 2>/dev/null || true)"
  [[ ${text_size} =~ ^[0-9]+$ ]] || text_size="${THEME_DESKTOP_TEXT_SIZE_BASE_PX}"
  read -r ui_size small_size < <(awk -v px="${text_size}" -v base="${THEME_DESKTOP_TEXT_SIZE_BASE_PX}" \
    -v ui="${THEME_DESKTOP_UI_FONT_PT}" -v small="${THEME_DESKTOP_SMALL_FONT_PT}" \
    'BEGIN { printf "%.2f %.2f\n", px * ui / base, px * small / base }')
  font_entries_ref=(
    "General:font=${desktop_settings_ref[FONT]},${ui_size},${regular}"
    "General:menuFont=${desktop_settings_ref[FONT]},${ui_size},${regular}"
    "General:toolBarFont=${desktop_settings_ref[FONT]},${ui_size},${regular}"
    "General:fixed=${desktop_settings_ref[MONOSPACE_FONT]},${ui_size},${regular}"
    "General:smallestReadableFont=${desktop_settings_ref[FONT]},${small_size},${regular}"
    "WM:activeFont=${desktop_settings_ref[FONT]},${ui_size},${regular}"
  )
}

theme_desktop_configure_qt_kde_bridge() {
  local -n desktop_settings_ref="$1"
  local -a font_entries=()
  theme_desktop_kde_font_entries "${!desktop_settings_ref}" font_entries

  # A global per-window scheme makes KColorSchemeManager ignore system palette changes.
  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/kdeglobals" \
    "General:ColorScheme=${desktop_settings_ref[RESOLVED_KDE_COLOR_SCHEME]}" \
    "Icons:Theme=${desktop_settings_ref[ICON_THEME]}" \
    "KDE:widgetStyle=${desktop_settings_ref[RESOLVED_QT_STYLE]}" \
    "UiSettings:ColorScheme=" \
    "${font_entries[@]}" || return 1

  theme_desktop_ini_write_batch "${XDG_CONFIG_HOME}/kdedefaults/kdeglobals" \
    "General:ColorScheme=${desktop_settings_ref[RESOLVED_KDE_COLOR_SCHEME]}" \
    "Icons:Theme=${desktop_settings_ref[ICON_THEME]}" \
    "KDE:widgetStyle=${desktop_settings_ref[RESOLVED_QT_STYLE]}" || return 1

  if [[ "${desktop_settings_ref[RESOLVED_KDE_COLOR_SCHEME]:-}" == "Hypr" ]]; then
    theme_desktop_install_kdeglobals_color_sections "${XDG_CONFIG_HOME}/kdeglobals" || return 1
    theme_desktop_install_kdeglobals_color_sections "${XDG_CONFIG_HOME}/kdedefaults/kdeglobals" || return 1
  fi
}

# GTK3 and GTK4 take the same key set; only the file differs.
theme_desktop_write_gtk_settings() {
  local -n desktop_settings_ref="$1"
  shift
  local settings_file="$1"
  local prefer_dark="$2"
  local gtk3_font="$3"
  local gtk3_font_size="$4"

  mkdir -p "${settings_file%/*}" || return 1
  theme_desktop_ini_write_batch "${settings_file}" \
    "Settings:gtk-theme-name=${desktop_settings_ref[RESOLVED_GTK_THEME]}" \
    "Settings:gtk-icon-theme-name=${desktop_settings_ref[ICON_THEME]}" \
    "Settings:gtk-cursor-theme-name=${desktop_settings_ref[CURSOR_THEME]}" \
    "Settings:gtk-cursor-theme-size=${desktop_settings_ref[CURSOR_SIZE]}" \
    "Settings:gtk-font-name=${gtk3_font} ${gtk3_font_size}" \
    "Settings:gtk-application-prefer-dark-theme=${prefer_dark}"
}

theme_desktop_write_gtk4_settings() {
  local -n desktop_settings_ref="$1"
  shift
  theme_desktop_write_gtk_settings "${!desktop_settings_ref}" "${XDG_CONFIG_HOME}/gtk-4.0/settings.ini" "$@"
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
  local -n desktop_settings_ref="$1"
  local gtk4_css="${XDG_CONFIG_HOME}/gtk-4.0/gtk.css"
  local theme_gtk4_css=""

  case "${desktop_settings_ref[RESOLVED_GTK_THEME]}" in
    Hypr-Gtk | Hypr-Gtk-Alt)
      theme_gtk4_css="${XDG_DATA_HOME:-$HOME/.local/share}/themes/Hypr-Gtk/gtk-4.0/gtk.css"
      ;;
    Adwaita|"")
      :
      ;;
    *)
      if [[ -f "${HOME}/.themes/${desktop_settings_ref[RESOLVED_GTK_THEME]}/gtk-4.0/gtk.css" ]]; then
        theme_gtk4_css="${HOME}/.themes/${desktop_settings_ref[RESOLVED_GTK_THEME]}/gtk-4.0/gtk.css"
      elif [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/themes/${desktop_settings_ref[RESOLVED_GTK_THEME]}/gtk-4.0/gtk.css" ]]; then
        theme_gtk4_css="${XDG_DATA_HOME:-$HOME/.local/share}/themes/${desktop_settings_ref[RESOLVED_GTK_THEME]}/gtk-4.0/gtk.css"
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

theme_desktop_write_gtkrc() {
  local -n desktop_settings_ref="$1"
  shift
  local gtkrc_file="$1"
  local font="$2"
  local font_size="$3"
  local prefer_dark="$4"

  theme_desktop_write_generated_file "${gtkrc_file}" <<EOF
# Generated by hypr theme desktop sync.
include "${HOME}/.gtkrc-2.0.mime"
gtk-theme-name="${desktop_settings_ref[RESOLVED_GTK_THEME]}"
gtk-icon-theme-name="${desktop_settings_ref[ICON_THEME]}"
gtk-font-name="${font} ${font_size}"
gtk-cursor-theme-name="${desktop_settings_ref[CURSOR_THEME]}"
gtk-cursor-theme-size=${desktop_settings_ref[CURSOR_SIZE]}
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
}

theme_desktop_write_xsettingsd() {
  local -n desktop_settings_ref="$1"
  shift
  local xsettingsd_file="$1"
  local font="$2"
  local font_size="$3"
  local prefer_dark="$4"

  theme_desktop_write_generated_file "${xsettingsd_file}" <<EOF
# Generated by hypr theme desktop sync.
Net/ThemeName "${desktop_settings_ref[RESOLVED_GTK_THEME]}"
Net/IconThemeName "${desktop_settings_ref[ICON_THEME]}"
Gtk/CursorThemeName "${desktop_settings_ref[CURSOR_THEME]}"
Gtk/CursorThemeSize ${desktop_settings_ref[CURSOR_SIZE]}
Gtk/FontName "${font} ${font_size}"
Gtk/ApplicationPreferDarkTheme ${prefer_dark}
Net/EnableEventSounds 1
Net/EnableInputFeedbackSounds 0
Xft/Antialias 1
Xft/Hinting 1
Xft/HintStyle "hintfull"
Xft/RGBA "rgb"
EOF
}

theme_desktop_flatpak_override() {
  local -n desktop_settings_ref="$1"
  command -v flatpak >/dev/null 2>&1 || return 0
  flatpak \
    --user override \
    --filesystem="${HOME}/.icons" \
    --filesystem="${XDG_DATA_HOME:-$HOME/.local/share}/icons" \
    --env=GTK_THEME="${desktop_settings_ref[RESOLVED_GTK_THEME]}" \
    --env=ICON_THEME="${desktop_settings_ref[ICON_THEME]}" ||
    print_log -sec "theme" -warn flatpak "override failed"
}

theme_desktop_configure_gtk() {
  local -n desktop_settings_ref="$1"
  local gtk3_font="${GTK3_FONT:-${desktop_settings_ref[FONT]}}"
  local gtk3_font_size="${GTK3_FONT_SIZE:-${desktop_settings_ref[FONT_SIZE]}}"
  local prefer_dark=0

  [[ "${desktop_settings_ref[COLOR_SCHEME]}" == "prefer-dark" ]] && prefer_dark=1

  mkdir -p "${XDG_CONFIG_HOME}/gtk-3.0" "${XDG_CONFIG_HOME}/xsettingsd" || return 1
  theme_desktop_write_gtk3_css || return 1
  theme_desktop_write_gtkrc "${!desktop_settings_ref}" "${HOME}/.gtkrc-2.0" "${gtk3_font}" "${gtk3_font_size}" "${prefer_dark}" || return 1
  theme_desktop_write_gtk_settings "${!desktop_settings_ref}" "${XDG_CONFIG_HOME}/gtk-3.0/settings.ini" \
    "${prefer_dark}" "${gtk3_font}" "${gtk3_font_size}" || return 1
  theme_desktop_write_gtk4_settings "${!desktop_settings_ref}" "${prefer_dark}" "${gtk3_font}" "${gtk3_font_size}" || return 1
  theme_desktop_write_gtk4_css "${!desktop_settings_ref}" || return 1
  theme_desktop_flatpak_override "${!desktop_settings_ref}"
  theme_desktop_write_xsettingsd "${!desktop_settings_ref}" "${XDG_CONFIG_HOME}/xsettingsd/xsettingsd.conf" \
    "${gtk3_font}" "${gtk3_font_size}" "${prefer_dark}"
}

theme_desktop_notify_gtk_theme_changed() {
  if command -v pkill >/dev/null 2>&1; then
    pkill -HUP -x xsettingsd >/dev/null 2>&1 || true
  fi
}

theme_desktop_configure_xcursor_resources() {
  local -n desktop_settings_ref="$1"
  theme_desktop_update_xcursor_resource "${!desktop_settings_ref}" "${HOME}/.Xresources" true || return 1
  theme_desktop_update_xcursor_resource "${!desktop_settings_ref}" "${HOME}/.Xdefaults"
}

theme_desktop_dconf_payload() {
  local -n desktop_settings_ref="$1"
  cat <<EOF
[org/gnome/desktop/interface]
icon-theme='${desktop_settings_ref[ICON_THEME]}'
gtk-theme='${desktop_settings_ref[RESOLVED_GTK_THEME]}'
color-scheme='${desktop_settings_ref[COLOR_SCHEME]}'
cursor-theme='${desktop_settings_ref[CURSOR_THEME]}'
cursor-size=${desktop_settings_ref[CURSOR_SIZE]}
font-name='${desktop_settings_ref[FONT]} ${desktop_settings_ref[FONT_SIZE]}'
document-font-name='${desktop_settings_ref[DOCUMENT_FONT]} ${desktop_settings_ref[DOCUMENT_FONT_SIZE]}'
monospace-font-name='${desktop_settings_ref[MONOSPACE_FONT]} ${desktop_settings_ref[MONOSPACE_FONT_SIZE]}'
font-antialiasing='${desktop_settings_ref[FONT_ANTIALIASING]}'
EOF

  # dconf load does not validate against the schema, so an empty FONT_HINTING
  # would be stored as '', outside the key's enum, and GSettings then silently
  # serves the schema default instead.
  [[ -n "${desktop_settings_ref[FONT_HINTING]:-}" ]] && printf "font-hinting='%s'\n" "${desktop_settings_ref[FONT_HINTING]}"

  cat <<EOF

[org/cinnamon/desktop/interface]
icon-theme='${desktop_settings_ref[ICON_THEME]}'
gtk-theme='${desktop_settings_ref[RESOLVED_GTK_THEME]}'
cursor-theme='${desktop_settings_ref[CURSOR_THEME]}'
cursor-size=${desktop_settings_ref[CURSOR_SIZE]}
font-name='${desktop_settings_ref[FONT]} ${desktop_settings_ref[FONT_SIZE]}'

[org/gnome/desktop/default-applications/terminal]
exec='$(command -v "${desktop_settings_ref[TERMINAL]}")'

[org/gnome/desktop/wm/preferences]
button-layout='${desktop_settings_ref[BUTTON_LAYOUT]}'
EOF
}

theme_desktop_write_dconf_content() {
  local -n desktop_settings_ref="$1"
  local dconf_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/dconf"
  local dconf_tmp=""

  mkdir -p "${dconf_file%/*}"
  dconf_tmp="$(mktemp "${dconf_file}.tmp.XXXXXX")" || return 1
  theme_desktop_dconf_payload "${!desktop_settings_ref}" >"${dconf_tmp}" || {
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
  local portal_reset_script="${HYPR_LIB_DIR}/system/reset-xdg-portal.sh"
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

theme_desktop_prepare_settings_into() {
  local -n desktop_settings_ref="$1"
  theme_desktop_resolve_settings_into "${!desktop_settings_ref}" || return 1
  theme_desktop_sync_gtk_theme_links "${!desktop_settings_ref}"
}

theme_desktop_static_state_hash() {
  local -n desktop_settings_ref="$1"
  local flatpak_installed=0
  local active_palette="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/active-palette.json"
  local qtct_kde_colors="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/Hypr.colors"
  local source_file=""
  local source_hash=""
  local -a source_files=("${BASH_SOURCE[0]}" "${BASH_SOURCE[0]%/*}/desktop.settings.bash")

  command -v flatpak >/dev/null 2>&1 && flatpak_installed=1
  for source_file in "${active_palette}" "${qtct_kde_colors}"; do
    [[ -f "${source_file}" ]] && source_files+=("${source_file}")
  done
  source_hash="$(hypr_hash_cache_digest_files "${source_files[@]}")" || return 1

  hypr_hash_cache_digest_strings \
    "source_hash=${source_hash}" \
    "gtk_theme=${desktop_settings_ref[RESOLVED_GTK_THEME]}" \
    "icon_theme=${desktop_settings_ref[ICON_THEME]}" \
    "cursor_theme=${desktop_settings_ref[CURSOR_THEME]}" \
    "cursor_size=${desktop_settings_ref[CURSOR_SIZE]}" \
    "terminal=${desktop_settings_ref[TERMINAL]}" \
    "font=${desktop_settings_ref[FONT]}" \
    "font_size=${desktop_settings_ref[FONT_SIZE]}" \
    "document_font=${desktop_settings_ref[DOCUMENT_FONT]}" \
    "document_font_size=${desktop_settings_ref[DOCUMENT_FONT_SIZE]}" \
    "monospace_font=${desktop_settings_ref[MONOSPACE_FONT]}" \
    "monospace_font_size=${desktop_settings_ref[MONOSPACE_FONT_SIZE]}" \
    "button_layout=${desktop_settings_ref[BUTTON_LAYOUT]}" \
    "font_antialiasing=${desktop_settings_ref[FONT_ANTIALIASING]}" \
    "font_hinting=${desktop_settings_ref[FONT_HINTING]}" \
    "kde_color_scheme=${desktop_settings_ref[RESOLVED_KDE_COLOR_SCHEME]}" \
    "qt_style=${desktop_settings_ref[RESOLVED_QT_STYLE]}" \
    "flatpak_installed=${flatpak_installed}"
}

theme_desktop_static_targets_ready() {
  local -n desktop_settings_ref="$1"
  local required_target=""
  local -a required_targets=(
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

  if [[ "${desktop_settings_ref[RESOLVED_KDE_COLOR_SCHEME]:-}" == "Hypr" ]]; then
    required_targets+=("${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/Hypr.colors")
  fi

  for required_target in "${required_targets[@]}"; do
    [[ -e "${required_target}" ]] || return 1
  done
}

theme_desktop_apply_runtime_resolved() {
  local -n desktop_settings_ref="$1"
  theme_desktop_export_cursor_environment "${!desktop_settings_ref}"
  theme_desktop_export_session_qt_env
  theme_desktop_write_dconf_content "${!desktop_settings_ref}" || return 1
  theme_desktop_restart_portal_backends_if_needed
  if [[ "${THEME_DESKTOP_SYNC_LOG_DCONF:-1}" -eq 1 ]]; then
    print_log -sec "dconf" -stat "Loaded dconf settings" "::"
    print_log -y "#-----------------------------------------------#"
    theme_desktop_dconf_payload "${!desktop_settings_ref}"
    print_log -y "#-----------------------------------------------#"
  fi
  return 0
}

theme_desktop_apply_static_resolved() {
  local -n desktop_settings_ref="$1"
  theme_desktop_install_kde_color_scheme || return 1
  theme_desktop_configure_qt_kde_bridge "${!desktop_settings_ref}" || return 1
  theme_desktop_ini_write_batch "${XDG_DATA_HOME}/icons/default/index.theme" "Icon Theme:Inherits=${desktop_settings_ref[CURSOR_THEME]}" || return 1
  theme_desktop_ini_write_batch "${HOME}/.icons/default/index.theme" "Icon Theme:Inherits=${desktop_settings_ref[CURSOR_THEME]}" || return 1
  theme_desktop_configure_gtk "${!desktop_settings_ref}" || return 1
  theme_desktop_configure_xcursor_resources "${!desktop_settings_ref}" || return 1
  theme_desktop_notify_gtk_theme_changed
  # Dolphin re-renders its cached icons only on a palette change, so the icon theme must switch first.
  theme_desktop_notify_kde_icons_changed
  theme_desktop_notify_kde_palette_changed
  theme_desktop_notify_kde_fonts_changed
}

theme_desktop_apply_static_resolved_if_needed() {
  local -n desktop_settings_ref="$1"
  local static_hash=""
  local hash_file=""

  hash_file="$(hypr_hash_cache_runtime_file "theme-desktop-static.hash")" || return 1
  static_hash="$(theme_desktop_static_state_hash "${!desktop_settings_ref}")" || return 1

  # hypr_hash_cache_is_current honors FORCE_COLOR_REGEN; store honors
  # HYPR_HASH_CACHE_ENABLE — no per-callsite flag checks needed.
  if theme_desktop_static_targets_ready "${!desktop_settings_ref}" \
    && hypr_hash_cache_is_current "${hash_file}" "${static_hash}"; then
    print_log -sec "theme" -stat "skip" "static desktop sync unchanged"
    return 0
  fi

  theme_desktop_apply_static_resolved "${!desktop_settings_ref}" || return 1
  hypr_hash_cache_store "${hash_file}" "${static_hash}" || return 1
}

theme_desktop_sync_runtime() {
  local -A resolved_settings=()
  theme_desktop_prepare_settings_into resolved_settings || return 1
  theme_desktop_apply_runtime_resolved resolved_settings || return 1
  theme_desktop_set_cursor_async resolved_settings
}

theme_desktop_sync_static() {
  local -A resolved_settings=()
  theme_desktop_prepare_settings_into resolved_settings || return 1
  theme_desktop_apply_static_resolved_if_needed resolved_settings
}

theme_desktop_sync_full() {
  local -A resolved_settings=()
  theme_desktop_prepare_settings_into resolved_settings || return 1
  theme_desktop_apply_static_resolved_if_needed resolved_settings || return 1
  theme_desktop_apply_runtime_resolved resolved_settings || return 1
  theme_desktop_apply_cursor_theme resolved_settings
}
