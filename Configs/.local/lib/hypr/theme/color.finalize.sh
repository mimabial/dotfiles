#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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
