#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system || exit 1
hypr_runtime_load_state || exit 1

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/theme/color.targets.sh"

FONT_NAME="${1:-}"
UPDATED=()
GENERAL_FONT=""
DOCUMENT_FONT=""
MONOSPACE_FONT=""
BAR_FONT=""
MENU_FONT=""
TERMINAL_FONT=""
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
ALACRITTY_CONF="${XDG_CONFIG_HOME}/alacritty/alacritty.toml"
KITTY_CONF="${XDG_CONFIG_HOME}/kitty/kitty.conf"
FONTCONFIG_FILE="${XDG_CONFIG_HOME}/fontconfig/fonts.conf"

append_updated() {
  UPDATED+=("$1")
}

resolve_font_targets() {
  local general_font=""

  general_font="$(hypr_config_value_from_layers 'FONT' 2>/dev/null || true)"
  DOCUMENT_FONT="$(hypr_config_value_from_layers 'DOCUMENT_FONT' 2>/dev/null || true)"
  MONOSPACE_FONT="$(hypr_config_value_from_layers 'MONOSPACE_FONT' 2>/dev/null || true)"
  BAR_FONT="$(hypr_config_value_from_layers 'BAR_FONT' 2>/dev/null || true)"
  MENU_FONT="$(hypr_config_value_from_layers 'MENU_FONT' 2>/dev/null || true)"
  TERMINAL_FONT="$(hypr_config_value_from_layers 'TERMINAL_FONT' 2>/dev/null || true)"

  GENERAL_FONT="${general_font:-${FONT_NAME:-sans-serif}}"
  DOCUMENT_FONT="${DOCUMENT_FONT:-${GENERAL_FONT}}"
  MONOSPACE_FONT="${MONOSPACE_FONT:-${FONT_NAME:-monospace}}"
  BAR_FONT="${BAR_FONT:-${GENERAL_FONT:-${MONOSPACE_FONT}}}"
  MENU_FONT="${MENU_FONT:-${GENERAL_FONT:-${MONOSPACE_FONT}}}"
  TERMINAL_FONT="${TERMINAL_FONT:-${MONOSPACE_FONT}}"
}

apply_alacritty_font() {
  [[ -f "${ALACRITTY_CONF}" ]] || return 0
  local escaped_font=""
  escaped_font="$(sed_escape_replacement "${TERMINAL_FONT}")"
  sed -i "s|family = \".*\"|family = \"${escaped_font}\"|g" "${ALACRITTY_CONF}"
  append_updated 'Alacritty base font'
}

reload_kitty_instances() {
  hypr_user_pgrep -x kitty >/dev/null 2>&1 || return 0
  hypr_user_pkill -USR1 -x kitty 2>/dev/null || true
}

apply_kitty_font() {
  [[ -f "${KITTY_CONF}" ]] || return 0
  local escaped_font=""
  escaped_font="$(sed_escape_replacement "${TERMINAL_FONT}")"
  sed -i "s|^font_family .*|font_family ${escaped_font}|g" "${KITTY_CONF}"
  reload_kitty_instances
  append_updated 'Kitty base font'
}

apply_terminal_fonts() {
  apply_alacritty_font
  apply_kitty_font
}

apply_theme_terminal_overlays() {
  if [[ "${selected_color_mode:-0}" -eq 0 ]]; then
    process_theme_files
    append_updated 'Theme terminal overlays'
  fi
}

apply_fontconfig_alias() {
  [[ -f "${FONTCONFIG_FILE}" ]] || return 0
  local escaped_font=""
  escaped_font="$(sed_escape_replacement "${MONOSPACE_FONT}")"

  if command -v xmlstarlet >/dev/null 2>&1; then
    xmlstarlet ed -L \
      -u '//match[@target="pattern"][test/string="monospace"]/edit[@name="family"]/string' \
      -v "${MONOSPACE_FONT}" \
      "${FONTCONFIG_FILE}" 2>/dev/null && append_updated 'Fontconfig monospace alias'
    return 0
  fi

  sed -i "/<test qual=\"any\" name=\"family\">/,/<\\/edit>/ s|<string>.*</string>|<string>${escaped_font}</string>|" "${FONTCONFIG_FILE}"
  append_updated 'Fontconfig monospace alias'
}

sync_ui_fonts() {
  hyprshell fonts/font-sync.sh --bar-to "${BAR_FONT}" --rofi-to "${MENU_FONT}" >/dev/null 2>&1 || true
  append_updated 'Waybar and Rofi fonts'

  hyprshell waybar.py --restart-direct >/dev/null 2>&1 || true
  append_updated 'Waybar reload'

  hypr_user_pgrep -x rofi >/dev/null 2>&1 || return 0
  hypr_user_pkill -x rofi >/dev/null 2>&1 || true
  append_updated 'Rofi launcher'
}

sync_desktop_ui_fonts() {
  local desktop_sync_script="${LIB_DIR}/hypr/theme/desktop.sync.sh"

  if [[ -x "${desktop_sync_script}" ]]; then
    THEME_DESKTOP_SYNC_LOG_DCONF=0 "${desktop_sync_script}" --full --quiet >/dev/null 2>&1 || true
    append_updated 'Desktop UI fonts'
  fi

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload config-only >/dev/null 2>&1 || true
    append_updated 'Hyprland font reload'
  fi
}

refresh_font_cache() {
  fc-cache -fq 2>/dev/null || return 0
  append_updated 'Font cache'
}

show_summary() {
  printf 'UI font set to: %s\n' "${GENERAL_FONT}"
  printf 'Monospace font set to: %s\n\n' "${MONOSPACE_FONT}"
  if [[ ${#UPDATED[@]} -eq 0 ]]; then
    printf 'No consumer configs were updated.\n'
    return 0
  fi

  printf 'Updated configurations:\n'
  printf '  • %s\n' "${UPDATED[@]}"
}

notify_user() {
  command -v dunstify >/dev/null 2>&1 || return 0
  dunstify -a 'Font Manager' -i 'preferences-desktop-font' \
    'Font Changed' "UI: ${GENERAL_FONT}\nMono: ${MONOSPACE_FONT}" -t 3000
}

resolve_font_targets
apply_terminal_fonts
apply_theme_terminal_overlays
apply_fontconfig_alias
sync_ui_fonts
sync_desktop_ui_fonts
refresh_font_cache
show_summary
notify_user
