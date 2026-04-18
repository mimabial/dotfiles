#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# theme.switch.sh - Theme switching orchestrator
#
# OVERVIEW:
#   Switches themes, updating all configuration files and
#   triggering color regeneration via color-sync.sh.
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

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

[ -z "${HYPR_THEME}" ] && echo "ERROR: unable to detect theme" && exit 1
get_themes

HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr/hyprland.conf}"
hypr_autoreload_prev=""
hypr_autoreload_set=0

# Lock file to prevent concurrent theme switching
THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"

exec 201>"${THEME_SWITCH_LOCK}"
! flock -n 201 && {
  print_log -sec "theme.switch" -stat "drop" "Another theme operation is already in progress"
  exit 0
}

for theme_switch_lib in \
  "${LIB_DIR}/hypr/theme/lib/theme.switch.config.bash" \
  "${LIB_DIR}/hypr/theme/lib/theme.switch.ui.bash"; do
  if [[ ! -r "${theme_switch_lib}" ]]; then
    print_log -sec "theme" -err "source" "missing ${theme_switch_lib}"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${theme_switch_lib}" || exit 1
done

disable_hypr_autoreload() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] || return 0
  command -v hyprctl >/dev/null 2>&1 || return 0

  hypr_autoreload_prev="$(hyprctl getoption misc:disable_autoreload 2>/dev/null | awk -F': ' '/int/ {print $2; exit}')"
  [[ -n "${hypr_autoreload_prev}" ]] || return 0

  hyprctl keyword misc:disable_autoreload 1 -q
  hypr_autoreload_set=1
}

cleanup_theme_switch() {
  local exit_code="${1:-$?}"
  theme_notify_finish "${exit_code}"
  if [[ "${hypr_autoreload_set}" -eq 1 ]] && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl keyword misc:disable_autoreload "${hypr_autoreload_prev}" -q
  fi
  flock -u 201 2>/dev/null || true
  return "${exit_code}"
}
trap 'cleanup_theme_switch "$?"' EXIT

quiet=false
parse_theme_switch_args() {
  while getopts "qnps:" option; do
    case $option in
      n) select_adjacent_theme n ;;
      p) select_adjacent_theme p ;;
      s) themeSet="$OPTARG" ;;
      q) quiet=true ;;
      *)
        echo "... invalid option ..."
        echo "$(basename "${0}") -[option]"
        echo "n : set next theme"
        echo "p : set previous theme"
        echo "s : set input theme"
        exit 1
        ;;
    esac
  done
}

set_active_theme() {
  local theme_exists=0
  local theme_name=""

  for theme_name in "${thmList[@]}"; do
    if [[ "${theme_name}" == "${themeSet}" ]]; then
      theme_exists=1
      break
    fi
  done

  [[ "${theme_exists}" -eq 1 ]] || themeSet="${HYPR_THEME}"
  state_set "HYPR_THEME" "${themeSet}" "staterc"
  print_log -sec "theme" -stat "apply" "${themeSet}"
  declare -F export_hypr_config >/dev/null 2>&1 && export_hypr_config
  # shellcheck source=/dev/null
  [[ -f "${HYPR_CONFIG_HOME}/env-theme" ]] && source "${HYPR_CONFIG_HOME}/env-theme"
}

load_active_theme_variables() {
  [[ -r "${HYPRLAND_CONFIG}" ]] || return 0
  [[ -r "${HYPR_THEME_DIR}/hypr.theme" ]] && sanitize_hypr_theme "${HYPR_THEME_DIR}/hypr.theme" "${XDG_CONFIG_HOME}/hypr/themes/theme.conf"
  load_hypr_variables "${HYPR_THEME_DIR}/hypr.theme"
  local _state_conf="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/hyprland.conf"
  [[ -r "${_state_conf}" ]] && load_hypr_variables "${_state_conf}"
  [[ -n "${GTK_THEME}" ]] || GTK_THEME="$(hypr_config_value_from_layers "GTK_THEME" 2>/dev/null || true)"
  [[ -n "${ICON_THEME}" ]] || ICON_THEME="$(hypr_config_value_from_layers "ICON_THEME" 2>/dev/null || true)"
  [[ -n "${CURSOR_THEME}" ]] || CURSOR_THEME="$(hypr_config_value_from_layers "CURSOR_THEME" 2>/dev/null || true)"
  [[ -n "${CURSOR_SIZE}" ]] || CURSOR_SIZE="$(hypr_config_value_from_layers "CURSOR_SIZE" 2>/dev/null || true)"
  [[ -n "${TERMINAL}" ]] || TERMINAL="$(hypr_config_value_from_layers "TERMINAL" 2>/dev/null || true)"
  [[ -n "${FONT}" ]] || FONT="$(hypr_config_value_from_layers "FONT" 2>/dev/null || true)"
  [[ -n "${FONT_STYLE}" ]] || FONT_STYLE="$(hypr_config_value_from_layers "FONT_STYLE" 2>/dev/null || true)"
  [[ -n "${FONT_SIZE}" ]] || FONT_SIZE="$(hypr_config_value_from_layers "FONT_SIZE" 2>/dev/null || true)"
  [[ -n "${DOCUMENT_FONT}" ]] || DOCUMENT_FONT="$(hypr_config_value_from_layers "DOCUMENT_FONT" 2>/dev/null || true)"
  [[ -n "${DOCUMENT_FONT_SIZE}" ]] || DOCUMENT_FONT_SIZE="$(hypr_config_value_from_layers "DOCUMENT_FONT_SIZE" 2>/dev/null || true)"
  [[ -n "${MONOSPACE_FONT}" ]] || MONOSPACE_FONT="$(hypr_config_value_from_layers "MONOSPACE_FONT" 2>/dev/null || true)"
  [[ -n "${MONOSPACE_FONT_SIZE}" ]] || MONOSPACE_FONT_SIZE="$(hypr_config_value_from_layers "MONOSPACE_FONT_SIZE" 2>/dev/null || true)"
}

main() {
  disable_hypr_autoreload
  parse_theme_switch_args "$@"
  set_active_theme
  load_active_theme_variables
  [[ "${quiet}" == "true" ]] || show_theme_status
  if [[ "${quiet}" == "true" ]]; then
    "${LIB_DIR}/hypr/theme/theme.apply.sh" --quiet || exit 1
  else
    "${LIB_DIR}/hypr/theme/theme.apply.sh" || exit 1
  fi
}

main "$@"
