#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# color.finalize.sh - Post-wal fixup: source the generated colors-shell.sh,
# update waybar border-radius, export icon theme, and persist the
# state-and-notify hand-off after color generation succeeds.
#
# Subsystem inputs (caller-scope globals consumed by these functions):
#   resolved_color_variant, selected_color_mode
#   color_variant_changed, selected_color_mode_changed
#   wal_cache_populate, wal_used_cache
: "${resolved_color_variant-}" "${selected_color_mode-}" \
  "${color_variant_changed-}" "${selected_color_mode_changed-}" \
  "${wal_cache_populate-}" "${wal_used_cache-}"

# Inlined from color.state.sh (deleted with the old pipeline).
color_state_persist() {
  [[ "${CACHE_ONLY:-0}" -eq 1 ]] && return 0

  local state_wallpaper="${STATE_WALLPAPER:-${WALLPAPER_IMAGE:-theme}}"
  local state_dir tmp_file
  state_dir="$(dirname "${STATE_FILE}")"
  tmp_file="${STATE_FILE}.tmp.$$"

  mkdir -p "${state_dir}" || return 1
  {
    echo "${wal_cache_key:-${state_wallpaper}:${resolved_color_variant}}"
    echo "wallpaper=${state_wallpaper}"
    echo "color_variant=${resolved_color_variant}"
    echo "selected_color_mode=${selected_color_mode}"
    echo "backend=${PYWAL_BACKEND}"
  } >"${tmp_file}" && mv -f "${tmp_file}" "${STATE_FILE}"
}

color_state_read_transition_metadata() {
  local variant_name="$1"
  local mode_name="$2"
  local state_file="${3:-${STATE_FILE}}"
  local state_line=""

  printf -v "${variant_name}" '%s' ""
  printf -v "${mode_name}" '%s' ""
  [[ -r "${state_file}" ]] || return 0

  state_line="$(awk -F= '
    /^color_variant=/ {variant=$2}
    /^selected_color_mode=/ {mode=$2}
    END {print variant "|" mode}
  ' "${state_file}" 2>/dev/null || true)"

  printf -v "${variant_name}" '%s' "${state_line%%|*}"
  printf -v "${mode_name}" '%s' "${state_line#*|}"
}

color_state_detect_transition_flags() {
  previous_color_variant=""
  previous_selected_color_mode=""
  color_variant_changed=false
  selected_color_mode_changed=false

  color_state_read_transition_metadata previous_color_variant previous_selected_color_mode
  [[ -n "${previous_color_variant}" && "${previous_color_variant}" != "${resolved_color_variant}" ]] && color_variant_changed=true
  [[ -n "${previous_selected_color_mode}" && "${previous_selected_color_mode}" != "${selected_color_mode}" ]] && selected_color_mode_changed=true
}

# Inlined from color.files.sh (deleted with the old pipeline).
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

color_finalize_resolve_path() {
  local input_path="$1"
  local resolved_path=""

  if command -v realpath >/dev/null 2>&1; then
    realpath "${input_path}" 2>/dev/null && return 0
  fi
  if command -v readlink >/dev/null 2>&1; then
    resolved_path="$(readlink -- "${input_path}" 2>/dev/null || readlink "${input_path}" 2>/dev/null || true)"
    if [[ -n "${resolved_path}" ]]; then
      case "${resolved_path}" in
        /*) printf '%s\n' "${resolved_path}" ;;
        *) printf '%s/%s\n' "$(cd "$(dirname "${input_path}")" && pwd -P)" "${resolved_path}" ;;
      esac
      return 0
    fi
  fi
  printf '%s\n' "${input_path}"
}

color_finalize_generated_outputs() {
  print_log -sec "pywal16" -stat "complete" "color generation"
  canonicalize_shell_colors_file

  post_process_generated_color_files

  if [[ "${wal_cache_populate}" -eq 1 ]] && [[ "${wal_used_cache}" -eq 0 ]] && [[ -n "${wal_cache_path}" ]]; then
    wal_cache_store "${WAL_CACHE}" "${wal_cache_path}" || print_log -sec "pywal16" -warn "cache" "store failed"
  fi

}

color_finalize_load_generated_colors() {
  color_finalize_source_generated_colors || return 1
  link_generated_color_files

  print_log -sec "pywal16" -stat "complete" "color files ready"
}

color_finalize_source_generated_colors() {
  set -a
  # shellcheck source=/dev/null
  source "${WAL_CACHE}/colors-shell.sh" || return 1
  set +a
}

color_finalize_normalize_hyprshade_colors() {
  local hyprshade_colors_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wal/colors.inc"

  if [[ -L "${hyprshade_colors_file}" ]]; then
    hyprshade_colors_file="$(color_finalize_resolve_path "${hyprshade_colors_file}")"
  fi

  if [[ -f "${hyprshade_colors_file}" ]]; then
    sed -i 's/vec3(\([0-9]\+\), \([0-9]\+\), \([0-9]\+\))/vec3(\1\/255.0, \2\/255.0, \3\/255.0)/g' "${hyprshade_colors_file}"
  fi
}

color_finalize_read_hypr_border() {
  local theme_conf="${1:-${HYPR_THEME_METADATA_FILE:-${HYPR_CONFIG_HOME}/themes/theme.conf}}"

  [[ -r "${theme_conf}" ]] || return 1
  awk -F= '
    /^[[:space:]]*rounding[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "${theme_conf}"
}

color_finalize_primary_theming() {
  local theme_conf="${HYPR_THEME_METADATA_FILE:-${HYPR_CONFIG_HOME}/themes/theme.conf}"

  print_log -sec "pywal16" -stat "deploy" "applying themes to applications"

  if [[ -f "${theme_conf}" ]]; then
    hypr_border="$(color_finalize_read_hypr_border "${theme_conf}" || true)"
    export hypr_border
  fi

  write_primary_app_theme_outputs || return 1

  color_finalize_normalize_hyprshade_colors
  signal_and_reload_live_apps kitty tmux rmpc

  if [[ "${selected_color_mode}" -eq 0 ]]; then
    process_theme_files
  fi
}

color_finalize_export_icon_theme() {
  local theme_conf="${HYPR_THEME_METADATA_FILE:-${HYPR_CONFIG_HOME}/themes/theme.conf}"
  local hyq_out=""
  local hyq_icon=""

  if command -v hyq &>/dev/null; then
    if [[ "${selected_color_mode}" -eq 0 ]] && [[ -r "${theme_conf}" ]]; then
      hyq_out="$(hyq "${theme_conf}" --export env --allow-missing -Q "\$ICON_THEME[string]" 2>/dev/null)"
      hyq_icon="$(_safe_hyq_get "${hyq_out}" "ICON_THEME")"
      [[ -n "${hyq_icon}" ]] && ICON_THEME="${hyq_icon}"
    elif [[ -z "${ICON_THEME}" ]]; then
      hyq_out="$(hyq "${HYPR_CONFIG_HOME}/hyprland.conf" --source --export env --allow-missing -Q "\$ICON_THEME[string]" 2>/dev/null)"
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

color_finalize_secondary_theming() {
  write_secondary_app_theme_outputs || return 1
  if [[ "${HYPR_THEME_DEFER_SECONDARY_UPDATES:-0}" -eq 1 ]]; then
    color_lock_release_theme_update
    return 0
  fi
  color_finalize_update_waybar_border_radius
  color_lock_release_theme_update

  if [[ "${ASYNC_POST_UPDATES}" -eq 1 ]]; then
    post_updates &>/dev/null &
  else
    post_updates &>/dev/null
  fi
}

color_finalize_render_pipeline() {
  [[ "${selected_color_mode}" -eq 1 ]] || return 0
  command -v hypr-theme >/dev/null 2>&1 || return 0

  local variant="${resolved_color_variant:-dark}"
  [[ "${variant}" =~ ^(dark|light)$ ]] || variant="dark"

  python3 "${LIB_DIR}/hypr/render/_palette.py" --from-wal-cache --variant "${variant}" \
    >/dev/null 2>&1 || {
      print_log -sec "render" -warn "palette" "from-wal-cache failed"
      return 0
    }
  HYPR_COLOR_VARIANT="${variant}" hypr-theme refresh >/dev/null 2>&1 \
    || print_log -sec "render" -warn "refresh" "pipeline failed"
}

color_finalize_terminal_output() {
  [[ -t 1 ]] || return 0
  [[ -f "${LIB_DIR}/hypr/util/print-colors.sh" ]] && bash "${LIB_DIR}/hypr/util/print-colors.sh" || true
}

color_finalize_commit_state_and_notify() {
  color_state_detect_transition_flags
  color_state_persist

  if [[ "${CACHE_ONLY}" -ne 1 ]] \
    && [[ "${HYPR_THEME_BATCH_RELOADS:-0}" -ne 1 ]] \
    && [[ "${color_variant_changed}" == true || "${selected_color_mode_changed}" == true ]]; then
    command -v dunstify &>/dev/null \
      && dunstify "Theme Updated" "${resolved_color_variant} mode" -i preferences-desktop-theme -t 2000
  fi

  print_log -sec "pywal16" -stat "complete" "applied"
}
