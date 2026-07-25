#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# color.finalize.sh - Source generated colors and apply the remaining
# synchronous theme metadata updates.
#
# Subsystem inputs:
#   selected_color_source - active palette policy
: "${selected_color_source-}"

_safe_hyq_get() {
  local hyq_output="$1"
  local var_name="$2"
  local value
  value="$(
    awk -F= -v key="__${var_name}" '$1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/"/, "", value)
      print value
      exit
    }' <<<"${hyq_output}"
  )"
  if [[ "${value}" =~ \$\(|\`|\; ]]; then
    print_log -sec "hyq" -warn "security" "blocked unsafe value for ${var_name}"
    return 1
  fi
  echo "${value}"
}

color_finalize_source_generated_colors() {
  set -a
  # shellcheck source=/dev/null
  source "${WAL_CACHE}/colors-shell.sh" || return 1
  set +a
}

color_finalize_read_hypr_border() {
  local theme_conf="${1:-${HYPR_THEME_METADATA_FILE:-${HYPR_CONFIG_HOME}/themes/theme.meta}}"

  [[ -r "${theme_conf}" ]] || return 1
  awk -F= '
    /^[[:space:]]*rounding[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "${theme_conf}"
}

color_finalize_export_icon_theme() {
  local theme_conf="${HYPR_THEME_METADATA_FILE:-${HYPR_CONFIG_HOME}/themes/theme.meta}"
  local hyq_out=""
  local hyq_icon=""

  if command -v hyq &>/dev/null; then
    if [[ "${selected_color_source}" == "theme" ]] && [[ -r "${theme_conf}" ]]; then
      hyq_out="$(hyq "${theme_conf}" --export env --allow-missing -Q "\$ICON_THEME[string]" 2>/dev/null)"
      hyq_icon="$(_safe_hyq_get "${hyq_out}" "ICON_THEME")"
      [[ -n "${hyq_icon}" ]] && ICON_THEME="${hyq_icon}"
    elif [[ -z "${ICON_THEME}" ]] && [[ -r "${theme_conf}" ]]; then
      hyq_out="$(hyq "${theme_conf}" --export env --allow-missing -Q "\$ICON_THEME[string]" 2>/dev/null)"
      hyq_icon="$(_safe_hyq_get "${hyq_out}" "ICON_THEME")"
      ICON_THEME="${hyq_icon:-$ICON_THEME}"
    fi
  fi

  export ICON_THEME
}

color_finalize_update_waybar_border_radius() {
  local border_radius="${hypr_border:-}"

  [[ "${SKIP_WAYBAR_UPDATE:-0}" -ne 1 ]] || return 0
  [[ -n "${border_radius}" ]] || border_radius="$(color_finalize_read_hypr_border || true)"

  if [[ -x "${LIB_DIR}/hypr/waybar/waybar.py" ]]; then
    WAYBAR_BORDER_RADIUS="${border_radius}" "${LIB_DIR}/hypr/waybar/waybar.py" --update-border-radius &>/dev/null
    print_log -sec "waybar" -stat "updated" "border-radius from theme"
  fi
}
