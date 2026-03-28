#!/usr/bin/env bash
# shellcheck disable=SC2154

# shellcheck source=/dev/null
source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
[[ -f "${HYPR_CONFIG_HOME}/env-theme" ]] && source "${HYPR_CONFIG_HOME}/env-theme"

safe_hyq_source() {
  local hyq_output="$1"
  local allowed_vars='^__(GTK_THEME|ICON_THEME|COLOR_SCHEME|CURSOR_THEME|CURSOR_SIZE|TERMINAL|FONT|FONT_SIZE|DOCUMENT_FONT|DOCUMENT_FONT_SIZE|MONOSPACE_FONT|MONOSPACE_FONT_SIZE|BUTTON_LAYOUT|FONT_ANTIALIASING|FONT_HINTING)='
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

dconf_populate() {
  cat <<EOF
[org/gnome/desktop/interface]
icon-theme='$ICON_THEME'
gtk-theme='$GTK_THEME'
color-scheme='$COLOR_SCHEME'
cursor-theme='$CURSOR_THEME'
cursor-size=$CURSOR_SIZE
font-name='$FONT $FONT_SIZE'
document-font-name='$DOCUMENT_FONT $DOCUMENT_FONT_SIZE'
monospace-font-name='$MONOSPACE_FONT $MONOSPACE_FONT_SIZE'
font-antialiasing='$FONT_ANTIALIASING'
font-hinting='$FONT_HINTING'

[org/gnome/desktop/default-applications/terminal]
exec='$(command -v "${TERMINAL}")'

[org/gnome/desktop/wm/preferences]
button-layout='$BUTTON_LAYOUT'
EOF
}

set_default_color_scheme() {
  COLOR_SCHEME="prefer-${resolved_color_variant}"
  if [[ "${selected_color_mode:-1}" -ne 0 ]]; then
    GTK_THEME="Pywal16-Gtk"
  else
    GTK_THEME=""
  fi
}

load_theme_mode_gtk_values() {
  local theme_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"
  local theme_hyq_output=""

  [[ "${selected_color_mode:-1}" -eq 0 ]] || return 0
  [[ -r "${theme_conf}" ]] || return 0

  theme_hyq_output="$(
    hyq "${theme_conf}" --export env --allow-missing \
      -Q '$GTK_THEME[string]' \
      -Q '$ICON_THEME[string]' \
      -Q '$CURSOR_THEME[string]' \
      -Q '$CURSOR_SIZE'
  )"
  safe_hyq_source "${theme_hyq_output}"
  GTK_THEME=${__GTK_THEME:-$GTK_THEME}
  ICON_THEME=${__ICON_THEME:-$ICON_THEME}
  CURSOR_THEME=${__CURSOR_THEME:-$CURSOR_THEME}
  CURSOR_SIZE=${__CURSOR_SIZE:-$CURSOR_SIZE}
}

build_hyq_args() {
  hyq_args=(
    "${HYPRLAND_CONFIG}"
    --source
    --export env
    -Q '$COLOR_SCHEME[string]'
    -Q '$TERMINAL[string]'
    -Q '$FONT[string]'
    -Q '$FONT_SIZE'
    -Q '$DOCUMENT_FONT[string]'
    -Q '$DOCUMENT_FONT_SIZE'
    -Q '$MONOSPACE_FONT[string]'
    -Q '$MONOSPACE_FONT_SIZE'
    -Q '$BUTTON_LAYOUT[string]'
    -Q '$FONT_ANTIALIASING[string]'
    -Q '$FONT_HINTING[string]'
  )

  if [[ "${selected_color_mode:-1}" -ne 0 ]]; then
    hyq_args+=(
      -Q '$GTK_THEME[string]'
      -Q '$ICON_THEME[string]'
      -Q '$CURSOR_THEME[string]'
      -Q '$CURSOR_SIZE'
    )
  fi
}

load_config_values() {
  local query_output=""

  [[ -r "${HYPRLAND_CONFIG}" ]] || return 0
  command -v hyq >/dev/null 2>&1 || return 0

  load_theme_mode_gtk_values
  build_hyq_args
  query_output="$(hyq "${hyq_args[@]}")"
  safe_hyq_source "${query_output}"

  GTK_THEME=${__GTK_THEME:-$GTK_THEME}
  COLOR_SCHEME=${__COLOR_SCHEME:-$COLOR_SCHEME}
  ICON_THEME=${__ICON_THEME:-$ICON_THEME}
  CURSOR_THEME=${__CURSOR_THEME:-$CURSOR_THEME}
  CURSOR_SIZE=${__CURSOR_SIZE:-$CURSOR_SIZE}
  TERMINAL=${__TERMINAL:-$TERMINAL}
  FONT=${__FONT:-$FONT}
  FONT_SIZE=${__FONT_SIZE:-$FONT_SIZE}
  DOCUMENT_FONT=${__DOCUMENT_FONT:-$DOCUMENT_FONT}
  DOCUMENT_FONT_SIZE=${__DOCUMENT_FONT_SIZE:-$DOCUMENT_FONT_SIZE}
  MONOSPACE_FONT=${__MONOSPACE_FONT:-$MONOSPACE_FONT}
  MONOSPACE_FONT_SIZE=${__MONOSPACE_FONT_SIZE:-$MONOSPACE_FONT_SIZE}
  BUTTON_LAYOUT=${__BUTTON_LAYOUT:-$BUTTON_LAYOUT}
  FONT_ANTIALIASING=${__FONT_ANTIALIASING:-$FONT_ANTIALIASING}
  FONT_HINTING=${__FONT_HINTING:-$FONT_HINTING}
}

apply_color_scheme_inversion_if_needed() {
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

write_dconf_content() {
  local dconf_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/dconf"
  local new_content=""
  local new_hash=""
  local old_hash=""

  mkdir -p "$(dirname "${dconf_file}")"
  new_content="$(dconf_populate)"
  new_hash="$(printf '%s' "${new_content}" | md5sum | cut -d' ' -f1)"
  [[ -f "${dconf_file}" ]] && old_hash="$(md5sum "${dconf_file}" 2>/dev/null | cut -d' ' -f1)"

  if [[ "${new_hash}" == "${old_hash}" ]]; then
    print_log -sec "dconf" -stat "skip" "unchanged"
  else
    printf '%s\n' "${new_content}" > "${dconf_file}"
    if dconf load -f / < "${dconf_file}" >/dev/null 2>&1; then
      print_log -sec "dconf" -stat "loaded" "${dconf_file}"
    else
      print_log -sec "dconf" -warn "failed" "${dconf_file}"
    fi
  fi
}

set_cursor_async() {
  [[ -n "${CURSOR_THEME}" && -n "${CURSOR_SIZE}" ]] || return 0
  hyprctl setcursor "${CURSOR_THEME}" "${CURSOR_SIZE}" &>/dev/null &
}

log_dconf_result() {
  print_log -sec "dconf" -stat "Loaded dconf settings" "::"
  print_log -y "#-----------------------------------------------#"
  dconf_populate
  print_log -y "#-----------------------------------------------#"
}

export_dconf_variables() {
  export GTK_THEME ICON_THEME COLOR_SCHEME CURSOR_THEME CURSOR_SIZE TERMINAL \
    FONT FONT_SIZE DOCUMENT_FONT DOCUMENT_FONT_SIZE MONOSPACE_FONT MONOSPACE_FONT_SIZE \
    BAR_FONT MENU_FONT NOTIFICATION_FONT BUTTON_LAYOUT
}

set_default_color_scheme
load_config_values
apply_color_scheme_inversion_if_needed
write_dconf_content
set_cursor_async
log_dconf_result
export_dconf_variables
