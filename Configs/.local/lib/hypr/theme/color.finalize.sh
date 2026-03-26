#!/usr/bin/env bash

color_finalize_generated_outputs() {
  print_log -sec "pywal16" -stat "complete" "color generation"
  canonicalize_shell_colors_file

  if [[ -f "${LIB_DIR}/hypr/wal/wal.hyprlock.sh" ]]; then
    bash "${LIB_DIR}/hypr/wal/wal.hyprlock.sh"
    print_log -sec "hyprlock" -stat "generated" "integer rgba colors"
  fi

  post_process_generated_color_files

  if [[ "${wal_cache_populate}" -eq 1 ]] && [[ "${wal_used_cache}" -eq 0 ]] && [[ -n "${wal_cache_path}" ]]; then
    if [[ "${CACHE_ONLY}" -ne 1 ]]; then
      wal_cache_store_async "${WAL_CACHE}" "${wal_cache_path}"
    else
      wal_cache_store_with_lock "${WAL_CACHE}" "${wal_cache_path}" || print_log -sec "pywal16" -warn "cache" "store failed"
    fi
  fi

  queue_opposite_mode_precache
}

color_finalize_load_generated_colors() {
  set -a
  # shellcheck source=/dev/null
  source "${WAL_CACHE}/colors-shell.sh"
  set +a

  link_generated_color_files

  if [[ "${selected_color_mode}" -eq 0 ]]; then
    if ! generate_hypr_colors_from_theme; then
      print_log -sec "theme" -warn "colors" "falling back to pywal16 Hyprland colors"
      ln -sf "${WAL_CACHE}/colors-hyprland.conf" "${HOME}/.config/hypr/themes/colors.conf" 2>/dev/null || true
    fi
  fi

  print_log -sec "pywal16" -stat "complete" "color files ready"
}

color_finalize_normalize_hyprshade_colors() {
  local hyprshade_colors_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wal/colors.inc"

  if [[ -L "${hyprshade_colors_file}" ]]; then
    hyprshade_colors_file="$(readlink -f "${hyprshade_colors_file}")"
  fi

  if [[ -f "${hyprshade_colors_file}" ]]; then
    sed -i 's/vec3(\([0-9]\+\), \([0-9]\+\), \([0-9]\+\))/vec3(\1\/255.0, \2\/255.0, \3\/255.0)/g' "${hyprshade_colors_file}"
  fi
}

color_finalize_primary_theming() {
  local theme_conf="${HYPR_CONFIG_HOME}/themes/theme.conf"

  print_log -sec "pywal16" -stat "deploy" "applying themes to applications"

  if [[ -f "${theme_conf}" ]]; then
    hypr_border="$(grep "rounding" "${theme_conf}" | grep "=" | head -1 | awk '{print $NF}')"
    export hypr_border
  fi

  run_app_theming
  if [[ "${ASYNC_APPS}" -eq 1 ]]; then
    print_log -sec "pywal16" -stat "async" "app theming running in background (${#APP_THEMING_PIDS[@]} jobs)"
  fi
  wait_for_theming_jobs_when_async_disabled

  color_finalize_normalize_hyprshade_colors
  reload_live_apps

  if [[ "${selected_color_mode}" -eq 0 ]]; then
    process_theme_files
  else
    apply_wallpaper_mode_theme_fallbacks
  fi
}

color_finalize_export_icon_theme() {
  local theme_conf="${HYPR_CONFIG_HOME}/themes/theme.conf"
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
  [[ "${SKIP_WAYBAR_UPDATE}" -ne 1 ]] || return 0

  if [[ -x "${LIB_DIR}/hypr/waybar/waybar.py" ]]; then
    WAYBAR_BORDER_RADIUS="${hypr_border:-}" "${LIB_DIR}/hypr/waybar/waybar.py" --update-border-radius &>/dev/null
    print_log -sec "waybar" -stat "updated" "border-radius from theme"
  elif command -v hyprshell &>/dev/null; then
    WAYBAR_BORDER_RADIUS="${hypr_border:-}" hyprshell waybar --update-border-radius &>/dev/null
    print_log -sec "waybar" -stat "updated" "border-radius from theme"
  fi
}

color_finalize_secondary_theming() {
  [[ -f "${LIB_DIR}/hypr/wal/wal.hypr.sh" ]] && source "${LIB_DIR}/hypr/wal/wal.hypr.sh"
  run_secondary_theming
  wait_for_theming_jobs_when_async_disabled
  color_finalize_update_waybar_border_radius
  color_lock_release_theme_update

  if [[ "${ASYNC_POST_UPDATES}" -eq 1 ]]; then
    post_updates &>/dev/null &
  else
    post_updates &>/dev/null
  fi
}

color_finalize_terminal_output() {
  [[ -t 1 ]] && [[ -f "${LIB_DIR}/hypr/wal/wal.print.colors.sh" ]] && bash "${LIB_DIR}/hypr/wal/wal.print.colors.sh"
}

color_finalize_commit_state_and_notify() {
  color_state_detect_transition_flags
  color_state_persist

  if [[ "${CACHE_ONLY}" -ne 1 ]] && [[ "${color_variant_changed}" == true || "${selected_color_mode_changed}" == true ]]; then
    command -v dunstify &>/dev/null \
      && dunstify "Theme Updated" "${resolved_color_variant} mode" -i preferences-desktop-theme -t 2000
  fi

  print_log -sec "pywal16" -stat "complete" "applied"
}
