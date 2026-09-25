#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell fonts/font-apply [font-name]
Apply the configured (or given) fonts across terminals, Quickshell, Rofi, and GTK." "$@"

hypr_runtime_require state system || exit 1
hypr_runtime_load_state || exit 1

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/theme/color.targets.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/fonts/font.sync.lib.bash"

FONT_NAME="${1:-}"
UPDATED_CONFIGS=()
GENERAL_FONT=""
MONOSPACE_FONT=""
MENU_FONT=""
TERMINAL_FONT=""
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
FONTCONFIG_FILE="${XDG_CONFIG_HOME}/fontconfig/fonts.conf"

append_updated() {
  UPDATED_CONFIGS+=("$1")
}

resolve_font_targets() {
  local general_font=""

  general_font="$(hypr_config_value_from_layers 'FONT' 2>/dev/null || true)"
  MONOSPACE_FONT="$(hypr_config_value_from_layers 'MONOSPACE_FONT' 2>/dev/null || true)"
  MENU_FONT="$(hypr_config_value_from_layers 'MENU_FONT' 2>/dev/null || true)"
  TERMINAL_FONT="$(hypr_config_value_from_layers 'TERMINAL_FONT' 2>/dev/null || true)"

  GENERAL_FONT="${general_font:-${FONT_NAME:-sans-serif}}"
  MONOSPACE_FONT="${MONOSPACE_FONT:-${FONT_NAME:-monospace}}"
  MENU_FONT="${MENU_FONT:-${GENERAL_FONT:-${MONOSPACE_FONT}}}"
  TERMINAL_FONT="${TERMINAL_FONT:-${MONOSPACE_FONT}}"
}

apply_foot_font() {
  font_sync_apply_foot_family "${TERMINAL_FONT}" || return 0
  append_updated 'Foot base font'
}

reload_kitty_instances() {
  hypr_user_pgrep -x kitty >/dev/null 2>&1 || return 0
  hypr_user_pkill -USR1 -x kitty 2>/dev/null || true
}

apply_kitty_font() {
  font_sync_apply_kitty_family "${TERMINAL_FONT}" || return 0
  reload_kitty_instances
  append_updated 'Kitty base font'
}

apply_terminal_fonts() {
  apply_foot_font
  apply_kitty_font
}

apply_theme_terminal_overlays() {
  if [[ "${selected_color_source:-theme}" == "theme" ]]; then
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
  hyprshell fonts/font-sync.sh --rofi-to "${MENU_FONT}" >/dev/null 2>&1 || true
  append_updated 'Rofi fonts'

  hypr_user_pgrep -x rofi >/dev/null 2>&1 || return 0
  hypr_user_pkill -x rofi >/dev/null 2>&1 || true
  append_updated 'Rofi launcher'
}

sync_hyprlock_font() {
  "${LIB_DIR}/hypr/render/hyprlock.sh" >/dev/null 2>&1 || return 0
  append_updated 'Hyprlock font'
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
  if [[ ${#UPDATED_CONFIGS[@]} -eq 0 ]]; then
    printf 'No consumer configs were updated.\n'
    return 0
  fi

  printf 'Updated configurations:\n'
  printf '  • %s\n' "${UPDATED_CONFIGS[@]}"
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
sync_hyprlock_font
sync_desktop_ui_fonts
refresh_font_cache
show_summary
notify_user
