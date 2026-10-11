#!/usr/bin/env bash

theme_desktop_load_looknfeel_cursor_values() {
  local -n cursor_settings="$1"
  local color_variant="$2"
  local theme_slug=""
  local override_file=""
  local -A looknfeel_values=()

  [[ -n "${HYPR_THEME:-}" ]] || return 0
  theme_slug="$(LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' <<<"${HYPR_THEME,,}")"
  [[ -n "${theme_slug}" ]] || theme_slug="default"
  override_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/looknfeel.d/${theme_slug}.${color_variant:-dark}.lua"

  hypr_config_parse_layer_file "${override_file}" looknfeel_values
  [[ -n "${looknfeel_values[CURSOR_THEME]-}" ]] \
    && cursor_settings[CURSOR_THEME]="${looknfeel_values[CURSOR_THEME]}"
  [[ -n "${looknfeel_values[CURSOR_SIZE]-}" ]] \
    && cursor_settings[CURSOR_SIZE]="${looknfeel_values[CURSOR_SIZE]}"
  return 0
}

declare -ga theme_desktop_setting_keys=(
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

theme_desktop_resolve_base_values_into() {
  local -n settings_ref="$1"
  local selected_color_source="${2:-theme}"
  local ICON_THEME="" CURSOR_THEME="" CURSOR_SIZE="" TERMINAL="" FONT="" FONT_SIZE="" DOCUMENT_FONT="" DOCUMENT_FONT_SIZE="" MONOSPACE_FONT="" MONOSPACE_FONT_SIZE="" BUTTON_LAYOUT="" FONT_ANTIALIASING="" FONT_HINTING=""
  local env_theme_file="${HYPR_CONFIG_HOME}/env-theme"
  local layer_var=""
  local layer_value=""
  local -A theme_meta_values=()

  # shellcheck source=/dev/null
  [[ -f "${env_theme_file}" ]] && source "${env_theme_file}"
  hypr_config_layer_cache_load
  hypr_config_parse_layer_file "${HYPR_CONFIG_HOME}/themes/theme.meta" theme_meta_values
  for layer_var in "${theme_desktop_setting_keys[@]}"; do
    [[ -n "${!layer_var-}" ]] && continue
    layer_value="${HYPR_CONFIG_LAYER_CACHE[${layer_var}]-}"
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
  settings_ref=()
  for layer_var in "${theme_desktop_setting_keys[@]}"; do
    settings_ref["${layer_var}"]="${!layer_var}"
  done
  return 0
}

theme_desktop_resolve_settings_into() {
  local -n settings_ref="$1"
  local resolved_color_variant="${resolved_color_variant:-$(state_get_color_variant 2>/dev/null || true)}"
  resolved_color_variant="${resolved_color_variant:-dark}"

  local selected_color_source="$(state_resolve_color_source "${selected_color_source:-}" "${selected_color_mode:-}")"
  local selected_color_mode="$(state_resolve_color_mode "${selected_color_mode:-}" "${resolved_color_variant}")"

  theme_desktop_resolve_base_values_into "$1" "${selected_color_source}"
  settings_ref[COLOR_SCHEME]="prefer-${resolved_color_variant}"
  theme_desktop_load_looknfeel_cursor_values "$1" "${resolved_color_variant}"

  if [[ "${revert_colors:-0}" -eq 1 ]] \
    || [[ "${selected_color_mode:-0}" == "${STATE_COLOR_MODE_DARK}" && "${resolved_color_variant:-}" == "light" ]] \
    || [[ "${selected_color_mode:-0}" == "${STATE_COLOR_MODE_LIGHT}" && "${resolved_color_variant:-}" == "dark" ]]; then
    if [[ "${resolved_color_variant}" == "dark" ]]; then
      settings_ref[COLOR_SCHEME]="prefer-light"
    else
      settings_ref[COLOR_SCHEME]="prefer-dark"
    fi
  fi

  local resolved_gtk="Adwaita"
  local pack_dir="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME:-}"
  local generated_gtk_dir="${XDG_DATA_HOME:-$HOME/.local/share}/themes/Hypr-Gtk"
  if [[ -n "${HYPR_THEME:-}" && (-d "${pack_dir}/gtk-3.0" || -d "${pack_dir}/gtk-4.0") ]]; then
    resolved_gtk="${HYPR_THEME// /-}"
  elif [[ -f "${generated_gtk_dir}/gtk-3.0/gtk.css" || -f "${generated_gtk_dir}/gtk-4.0/gtk.css" ]]; then
    resolved_gtk="Hypr-Gtk"
    # render/gtk.py alternates two names for this folder on every build; GTK 3 reloads a theme only when its name changes.
    [[ -s "${generated_gtk_dir}/theme-name" ]] && read -r resolved_gtk <"${generated_gtk_dir}/theme-name" || true
  fi

  settings_ref[RESOLVED_GTK_THEME]="${resolved_gtk}"

  if [[ -f "${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/render/qtct/Hypr.colors" ]]; then
    settings_ref[RESOLVED_KDE_COLOR_SCHEME]="Hypr"
  elif [[ "${settings_ref[COLOR_SCHEME]}" == "prefer-light" ]]; then
    settings_ref[RESOLVED_KDE_COLOR_SCHEME]="KvGnome"
  else
    settings_ref[RESOLVED_KDE_COLOR_SCHEME]="KvGnomeDark"
  fi
  settings_ref[RESOLVED_QT_STYLE]="Breeze"

  return 0
}
