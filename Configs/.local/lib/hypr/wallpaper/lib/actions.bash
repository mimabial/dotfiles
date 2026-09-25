#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# The catalog entry the pipeline is acting on. This is the one place that reads
# the catalog; every step below takes the resolved path instead.
wallpaper_selected_path() {
  printf '%s\n' "${wallpaper_paths[selected_wallpaper_index]:-}"
}

wallpaper_prepare_notification_payload() {
  local wallpaper_path="${selected_wallpaper_path:-${1:-}}"
  local wallpaper_hash=""
  [[ -z "${wallpaper_path}" ]] || wallpaper_hash="${wallpaper_hash_by_path["${wallpaper_path}"]:-}"

  if [[ -z "${wallpaper_path}" && -e "${active_wallpaper_link}" ]]; then
    wallpaper_path="$(wallpaper_resolve_path "${active_wallpaper_link}")"
  fi

  if [[ -z "${selected_wallpaper:-}" && -n "${wallpaper_path}" ]]; then
    selected_wallpaper="$(basename "${wallpaper_path}")"
  fi

  if [[ -z "${selected_thumbnail:-}" && -n "${wallpaper_path}" ]]; then
    if [[ -z "${wallpaper_hash}" ]]; then
      wallpaper_hash="$(wallpaper_file_hash "${wallpaper_path}" 2>/dev/null || true)"
      [[ -n "${wallpaper_hash}" ]] && wallpaper_hash_by_path["${wallpaper_path}"]="${wallpaper_hash}"
    fi
    [[ -n "${wallpaper_hash}" ]] && selected_thumbnail="${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.sqre"
  fi

  export selected_wallpaper selected_wallpaper_path selected_thumbnail
  export HYPR_WALLPAPER_NOTIFY_NAME="${selected_wallpaper:-$(basename "${wallpaper_path:-wallpaper}")}"
  export HYPR_WALLPAPER_NOTIFY_ICON="${selected_thumbnail:-}"
}

wallpaper_should_apply_colors_async() {
  [[ "${set_as_global}" == "true" ]] || return 1
  [[ "${WALLPAPER_SKIP_COLORS:-0}" -eq 0 ]] || return 1
  [[ "${selected_color_source:-theme}" == "theme" ]] && return 1
  return 0
}

wallpaper_resolve_hypr_theme_cmd() {
  local hypr_theme_cmd=""

  hypr_theme_cmd="$(command -v hypr-theme 2>/dev/null || true)"
  if [[ -n "${hypr_theme_cmd}" ]]; then
    printf '%s\n' "${hypr_theme_cmd}"
    return 0
  fi

  if [[ -x "${HOME}/.local/bin/hypr-theme" ]]; then
    printf '%s\n' "${HOME}/.local/bin/hypr-theme"
    return 0
  fi

  return 1
}

wallpaper_resolve_color_variant() {
  local variant=""

  case "${selected_color_mode:-1}" in
    2)
      printf 'dark\n'
      return 0
      ;;
    3)
      printf 'light\n'
      return 0
      ;;
  esac

  if declare -F state_get_color_variant >/dev/null 2>&1; then
    variant="$(state_get_color_variant 2>/dev/null || true)"
  fi
  [[ "${variant}" =~ ^(dark|light)$ ]] || variant="${BACKGROUND_MODE:-}"
  [[ "${variant}" =~ ^(dark|light)$ ]] || variant="dark"
  printf '%s\n' "${variant}"
}

wallpaper_link_selected() {
  local wallpaper_path="$1"

  ln -fs "${wallpaper_path}" "${active_wallpaper_link}"
  ln -fs "${wallpaper_path}" "${current_wallpaper_link}"
  wallpaper_prepare_notification_payload "${wallpaper_path}"
}

wallpaper_refresh_hyprlock_background() {
  [[ "${WALLPAPER_SKIP_HYPRLOCK_BACKGROUND:-0}" -eq 1 ]] && return 0
  # Absolute path: this function is called from wallpaper.sh's resume path,
  # which runs inside the theme.apply phase-D systemd-run --user envelope.
  # That envelope does NOT inherit the hyprshell-extended PATH, so a bare
  # `hyprlock.sh` would silently fail there. The symlink (wall.set) has
  # already been updated by wallpaper_link_selected above, so backgrounding
  # the refresh is safe — the subprocess resolves the correct path.
  local hyprlock_script="${LIB_DIR}/hypr/session/hyprlock.sh"
  [[ -x "${hyprlock_script}" ]] || return 0
  run_detached run_low_prio "${hyprlock_script}" --background
}

wallpaper_run_color_refresh() {
  local wallpaper_path="${1:-}"
  local hypr_theme_cmd=""
  local theme_name="${HYPR_THEME:-}"
  local variant=""

  [[ -n "${wallpaper_path}" ]] || return 1

  hypr_theme_cmd="$(wallpaper_resolve_hypr_theme_cmd)" || return 1
  variant="$(wallpaper_resolve_color_variant)"

  if declare -F state_set >/dev/null 2>&1; then
    state_set "BACKGROUND_MODE" "${variant}" "staterc" || true
  fi
  if declare -F state_set_color_variant >/dev/null 2>&1; then
    state_set_color_variant "${variant}" || true
  fi

  if [[ -z "${theme_name}" ]] && declare -F state_get >/dev/null 2>&1; then
    theme_name="$(state_get "HYPR_THEME" "" 2>/dev/null || true)"
  fi

  HYPR_THEME="${theme_name}" HYPR_THEME_REQUIRE_CURRENT_WALLPAPER=1 \
    run_low_prio "${hypr_theme_cmd}" wallpaper --variant "${variant}" "${wallpaper_path}" &>/dev/null
}

wallpaper_background_post_apply() {
  [[ "${WALLPAPER_SKIP_POST_APPLY:-0}" -eq 1 ]] && return 0
  run_detached wallpaper_post_apply "$@"
}

wallpaper_post_apply() {
  wallpaper_enqueue_cache_jobs -w "$2" || true
  [[ "$1" -eq 1 ]] && wallpaper_run_color_refresh "$2"
}

# Fills in the hash for path if the map does not already hold one.
wallpaper_ensure_hash() {
  local hashmap_name="$1"
  local path="$2"
  local -n hash_ref="${hashmap_name}"

  [[ -n "${path}" ]] || return 1
  [[ -n "${hash_ref["${path}"]:-}" ]] || hash_ref["${path}"]="$(wallpaper_file_hash "${path}")"
  [[ -n "${hash_ref["${path}"]:-}" ]]
}

wallpaper_refresh_thumbnail_links() {
  local wallpaper_path="$1"
  local hash=""

  if ! wallpaper_ensure_hash wallpaper_hash_by_path "${wallpaper_path}"; then
    print_log -warn "wallpaper" "missing hash for ${wallpaper_path:-unknown}"
    return 1
  fi

  hash="${wallpaper_hash_by_path["${wallpaper_path}"]}"
  ln -fs "${WALLPAPER_THUMB_DIR}/${hash}.sqre" "${current_square_thumbnail_link}"
  ln -fs "${WALLPAPER_THUMB_DIR}/${hash}.thmb" "${current_thumbnail_link}"
  ln -fs "${WALLPAPER_THUMB_DIR}/${hash}.blur" "${current_blur_thumbnail_link}"
  ln -fs "${WALLPAPER_THUMB_DIR}/${hash}.quad" "${current_quad_thumbnail_link}"
}

apply_selected_wallpaper() {
  local apply_colors=0
  local wallpaper_path=""
  wallpaper_should_apply_colors_async && apply_colors=1

  if [[ "${WALLPAPER_RELOAD_ALL:-1}" -eq 1 ]] && [[ ${wallpaper_setter_flag} != "link" ]]; then
    print_log -sec "wallpaper" "Reloading themes and wallpapers"
  fi

  wallpaper_path="$(wallpaper_selected_path)"
  wallpaper_link_selected "${wallpaper_path}"
  wallpaper_refresh_hyprlock_background
  [[ "${set_as_global}" == "true" ]] || return 0

  print_log -sec "wallpaper" "Setting Wallpaper as global"
  wallpaper_background_post_apply "${apply_colors}" "${wallpaper_path}"
  wallpaper_refresh_thumbnail_links "${wallpaper_path}"
}

select_adjacent_wallpaper() {
  local direction="$1"
  local current_wallpaper="" index=""

  current_wallpaper="$(wallpaper_resolve_path "${active_wallpaper_link}")"

  if index="$(catalog_index_of wallpaper_paths "${current_wallpaper}")"; then
    selected_wallpaper_index="$(catalog_adjacent_index "${index}" "${direction}" "${#wallpaper_paths[@]}")" || return 1
  else
    selected_wallpaper_index=0
    print_log -sec "wallpaper" -warn "Current wallpaper not in theme list, resetting to first"
  fi

  apply_selected_wallpaper
}
