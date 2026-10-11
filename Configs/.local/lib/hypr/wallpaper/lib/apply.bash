#!/usr/bin/env bash

wallpaper_set_paths() {
  if [[ "${wallpaper_is_global}" == "true" ]]; then
    mkdir -p "${WALLPAPER_CURRENT_DIR}"
    active_wallpaper_link="${HYPR_THEME_DIR}/wall.set"
    current_wallpaper_link="${WALLPAPER_CURRENT_DIR}/wall.set"
    current_square_thumbnail_link="${WALLPAPER_CURRENT_DIR}/wall.sqre"
    current_thumbnail_link="${WALLPAPER_CURRENT_DIR}/wall.thmb"
    current_blur_thumbnail_link="${WALLPAPER_CURRENT_DIR}/wall.blur"
    current_quad_thumbnail_link="${WALLPAPER_CURRENT_DIR}/wall.quad"
  elif [[ -n "${wallpaper_backend}" ]]; then
    mkdir -p "${WALLPAPER_CURRENT_DIR}"
    current_wallpaper_link="${WALLPAPER_CURRENT_DIR}/${wallpaper_backend}.png"
    active_wallpaper_link="${HYPR_THEME_DIR}/wall.${wallpaper_backend}.png"
  else
    active_wallpaper_link="${HYPR_THEME_DIR}/wall.set"
  fi
}

# An adapter is wallpaper.<backend>.sh, beside this library or on PATH, called with the
# active wallpaper link. It must display synchronously when WALLPAPER_WAIT_FOR_LOCK or
# WALLPAPER_SYNC_APPLY is 1, and exit non-zero on failure so the caller can warn.
wallpaper_apply_backend() {
  [[ "${WALLPAPER_SKIP_BACKEND_APPLY:-0}" -eq 1 ]] && return 0
  [[ -n "${wallpaper_backend}" ]] || return 0
  if [[ -f "${HYPR_LIB_DIR}/wallpaper/wallpaper.${wallpaper_backend}.sh" ]]; then
    print_log -sec "wallpaper" "Using backend: ${wallpaper_backend}"
    WALLPAPER_WAIT_FOR_LOCK="${wallpaper_wait_for_lock}" \
      "${HYPR_LIB_DIR}/wallpaper/wallpaper.${wallpaper_backend}.sh" "${active_wallpaper_link}"
    return
  fi

  if command -v "wallpaper.${wallpaper_backend}.sh" >/dev/null 2>&1; then
    WALLPAPER_WAIT_FOR_LOCK="${wallpaper_wait_for_lock}" \
      "wallpaper.${wallpaper_backend}.sh" "${active_wallpaper_link}"
  else
    print_log -warn "wallpaper" "No backend script found for ${wallpaper_backend}"
    print_log -warn "wallpaper" "Created: $WALLPAPER_CURRENT_DIR/${wallpaper_backend}.png instead"
  fi
}

# The one place that reads the catalog; every step below takes the resolved path
# instead.
wallpaper_selected_path() {
  printf '%s\n' "${wallpaper_paths[selected_wallpaper_index]:-}"
}

wallpaper_should_apply_colors_async() {
  [[ "${wallpaper_is_global}" == "true" ]] || return 1
  [[ "${WALLPAPER_SKIP_COLORS:-0}" -eq 0 ]] || return 1
  [[ "${selected_color_source:-theme}" == "theme" ]] && return 1
  return 0
}

wallpaper_link_selected() {
  local wallpaper_path="$1"

  ln -fs "${wallpaper_path}" "${active_wallpaper_link}"
  [[ -z "${current_wallpaper_link:-}" ]] || ln -fs "${wallpaper_path}" "${current_wallpaper_link}"
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
  local hyprlock_script="${HYPR_LIB_DIR}/session/hyprlock.sh"
  [[ -x "${hyprlock_script}" ]] || return 0
  wallpaper_run_detached wallpaper_run_low_priority "${hyprlock_script}" --background
}

wallpaper_run_color_refresh() {
  local wallpaper_path="${1:-}"
  local hypr_theme_cmd=""
  local theme_name="${HYPR_THEME:-}"
  local variant=""

  [[ -n "${wallpaper_path}" ]] || return 1

  hypr_theme_cmd="$(command -v hypr-theme)" || return 1
  variant="$(state_resolve_color_variant "${selected_color_mode:-}")"

  if [[ -z "${theme_name}" ]] && declare -F state_get >/dev/null 2>&1; then
    theme_name="$(state_get "HYPR_THEME" "" 2>/dev/null || true)"
  fi

  HYPR_THEME="${theme_name}" HYPR_THEME_REQUIRE_CURRENT_WALLPAPER=1 \
    wallpaper_run_low_priority "${hypr_theme_cmd}" wallpaper --variant "${variant}" "${wallpaper_path}" &>/dev/null || return
  [[ "$(realpath -e -- "${current_wallpaper_link}" 2>/dev/null)" == "$(realpath -e -- "${wallpaper_path}")" ]] || return 0

  if declare -F state_set >/dev/null 2>&1; then
    state_set "BACKGROUND_MODE" "${variant}" "staterc" || true
  fi
  if declare -F state_set_color_variant >/dev/null 2>&1; then
    state_set_color_variant "${variant}" || true
  fi
}

wallpaper_background_post_apply() {
  [[ "${WALLPAPER_SKIP_POST_APPLY:-0}" -eq 1 ]] && return 0
  wallpaper_run_detached wallpaper_post_apply "$@"
}

wallpaper_post_apply() {
  local apply_colors="$1" wallpaper_path="$2"
  wallpaper_enqueue_cache_jobs -w "${wallpaper_path}" || print_log -warn "wallpaper" "Could not queue cache jobs for ${wallpaper_path}"
  [[ "${apply_colors}" -eq 1 ]] && wallpaper_run_color_refresh "${wallpaper_path}"
}

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

wallpaper_apply_selected() {
  local apply_colors=0
  local wallpaper_path=""
  wallpaper_should_apply_colors_async && apply_colors=1

  if [[ "${WALLPAPER_RELOAD_ALL:-1}" -eq 1 ]] && [[ ${wallpaper_action} != "link" ]]; then
    print_log -sec "wallpaper" "Reloading themes and wallpapers"
  fi

  wallpaper_path="$(wallpaper_selected_path)"
  wallpaper_link_selected "${wallpaper_path}"
  wallpaper_refresh_hyprlock_background
  [[ "${wallpaper_is_global}" == "true" ]] || return 0

  print_log -sec "wallpaper" "Setting Wallpaper as global"
  wallpaper_background_post_apply "${apply_colors}" "${wallpaper_path}"
  wallpaper_refresh_thumbnail_links "${wallpaper_path}"
}

wallpaper_select_adjacent() {
  local direction="$1"
  local current_wallpaper="" index=""

  current_wallpaper="$(wallpaper_resolve_path "${active_wallpaper_link}")"

  if index="$(catalog_index_of wallpaper_paths "${current_wallpaper}")"; then
    selected_wallpaper_index="$(catalog_adjacent_index "${index}" "${direction}" "${#wallpaper_paths[@]}")" || return 1
  else
    selected_wallpaper_index=0
    print_log -sec "wallpaper" -warn "Current wallpaper not in theme list, resetting to first"
  fi

  wallpaper_apply_selected
}

wallpaper_random_index() {
  local count="$1"
  local max_random=1073741824
  local accept_limit=0
  local candidate=0

  [[ "${count}" =~ ^[0-9]+$ ]] || return 1
  ((count > 0 && count <= max_random)) || return 1

  accept_limit=$((max_random - (max_random % count)))
  while :; do
    candidate=$(((RANDOM << 15) | RANDOM))
    if ((candidate < accept_limit)); then
      printf '%s\n' $((candidate % count))
      return 0
    fi
  done
}

wallpaper_select_current_or_first() {
  local missing_message="$1"
  local current_wallpaper="" index=""

  wallpaper_ensure_catalog
  current_wallpaper="$(wallpaper_resolve_path "${active_wallpaper_link}")"

  if index="$(catalog_index_of wallpaper_paths "${current_wallpaper}")"; then
    selected_wallpaper_index="${index}"
    return 0
  fi

  selected_wallpaper_index=0
  print_log -sec "wallpaper" -warn "${missing_message}"
}
