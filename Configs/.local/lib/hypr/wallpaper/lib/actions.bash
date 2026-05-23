#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Apply/set wallpaper links and trigger cache/color pipelines.

wallpaper_prepare_notification_payload() {
  local wallpaper_path="${selected_wallpaper_path:-${wallList[setIndex]:-}}"
  local wallpaper_hash="${wallHash[setIndex]:-}"

  if [[ -z "${wallpaper_path}" && -e "${active_wallpaper_link}" ]]; then
    wallpaper_path="$(wallpaper_resolve_path "${active_wallpaper_link}")"
  fi

  if [[ -z "${selected_wallpaper:-}" && -n "${wallpaper_path}" ]]; then
    selected_wallpaper="$(basename "${wallpaper_path}")"
  fi

  if [[ -z "${selected_thumbnail:-}" && -n "${wallpaper_path}" ]]; then
    if [[ -z "${wallpaper_hash}" ]]; then
      wallpaper_hash="$(set_hash "${wallpaper_path}" 2>/dev/null || true)"
      [[ -n "${wallpaper_hash}" ]] && wallHash[setIndex]="${wallpaper_hash}"
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
  [[ "${selected_color_mode:-1}" -eq 0 ]] && return 1
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
  local wallpaper_path="${wallList[setIndex]}"
  ln -fs "${wallpaper_path}" "${active_wallpaper_link}"
  ln -fs "${wallpaper_path}" "${current_wallpaper_link}"
  wallpaper_prepare_notification_payload
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
  run_low_prio "${hyprlock_script}" --background 202>&- &
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

  HYPR_THEME="${theme_name}" run_low_prio "${hypr_theme_cmd}" wallpaper --variant "${variant}" "${wallpaper_path}" &>/dev/null
}

wallpaper_background_post_apply() {
  local apply_colors="$1"
  local wallpaper_path="$2"

  [[ "${WALLPAPER_SKIP_POST_APPLY:-0}" -eq 1 ]] && return 0

  {
    wallpaper_enqueue_cache_jobs -w "${wallpaper_path}" || true
    [[ "${apply_colors}" -eq 1 ]] && wallpaper_run_color_refresh "${wallpaper_path}"
  } 202>&- &
}

wallpaper_ensure_hash() {
  [[ -n "${wallList[setIndex]:-}" ]] || return 1
  [[ -n "${wallHash[setIndex]:-}" ]] || wallHash[setIndex]="$(set_hash "${wallList[setIndex]}")"
  [[ -n "${wallHash[setIndex]:-}" ]]
}

wallpaper_refresh_thumbnail_links() {
  if ! wallpaper_ensure_hash; then
    print_log -warn "wallpaper" "missing hash for ${wallList[setIndex]:-unknown}"
    return 1
  fi

  ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.sqre" "${current_square_thumbnail_link}"
  ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.thmb" "${current_thumbnail_link}"
  ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.blur" "${current_blur_thumbnail_link}"
  ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.quad" "${current_quad_thumbnail_link}"
}

apply_selected_wallpaper() {
  local apply_colors=0
  local wallpaper_path=""
  wallpaper_should_apply_colors_async && apply_colors=1

  if [[ "${WALLPAPER_RELOAD_ALL:-1}" -eq 1 ]] && [[ ${wallpaper_setter_flag} != "link" ]]; then
    print_log -sec "wallpaper" "Reloading themes and wallpapers"
  fi

  wallpaper_link_selected
  wallpaper_path="${wallList[setIndex]}"
  wallpaper_refresh_hyprlock_background
  [[ "${set_as_global}" == "true" ]] || return 0

  print_log -sec "wallpaper" "Setting Wallpaper as global"
  wallpaper_background_post_apply "${apply_colors}" "${wallpaper_path}"
  wallpaper_refresh_thumbnail_links
}

select_adjacent_wallpaper() {
  local current_wallpaper found
  found=false
  current_wallpaper="$(wallpaper_resolve_path "${active_wallpaper_link}")"

  for i in "${!wallList[@]}"; do
    if [[ "${current_wallpaper}" == "${wallList[i]}" ]]; then
      found=true
      if [[ "${1}" == "n" ]]; then
        setIndex=$(((i + 1) % ${#wallList[@]}))
      elif [[ "${1}" == "p" ]]; then
        setIndex=$(((i - 1 + ${#wallList[@]}) % ${#wallList[@]}))
      fi
      break
    fi
  done

  if [[ "${found}" != true ]]; then
    setIndex=0
    print_log -sec "wallpaper" -warn "Current wallpaper not in theme list, resetting to first"
  fi

  apply_selected_wallpaper "${wallList[setIndex]}"
}
