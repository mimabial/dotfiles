#!/usr/bin/env bash

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
  wallpaper_action_emits_notification || return 1
  [[ "${WALLPAPER_SKIP_COLORS:-0}" -eq 0 ]] || return 1
  [[ "${selected_color_mode:-1}" -eq 0 ]] && return 1
}

apply_selected_wallpaper() {
  local apply_colors=0
  wallpaper_should_apply_colors_async && apply_colors=1

  # Experimental, set to 1 if stable
  if [[ "${WALLPAPER_RELOAD_ALL:-1}" -eq 1 ]] && [[ ${wallpaper_setter_flag} != "link" ]]; then
    print_log -sec "wallpaper" "Reloading themes and wallpapers"
  fi

  ln -fs "${wallList[setIndex]}" "${active_wallpaper_link}"
  ln -fs "${wallList[setIndex]}" "${current_wallpaper_link}"
  wallpaper_prepare_notification_payload

  # Update hyprlock background
  if command -v hyprlock.sh &>/dev/null; then
    run_low_prio hyprlock.sh --background 202>&- &
  fi

  if [[ "${set_as_global}" == "true" ]]; then
    print_log -sec "wallpaper" "Setting Wallpaper as global"
    {
      wallpaper_enqueue_cache_jobs -w "${wallList[setIndex]}" || true
      if [[ "${apply_colors}" -eq 1 ]]; then
        run_low_prio "${LIB_DIR}/hypr/theme/color.set.sh" "${wallList[setIndex]}" &>/dev/null
        # Sync nvim after colors are generated
        [[ -x "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" ]] && "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" >/dev/null 2>&1
        if declare -F wallpaper_notify_emit >/dev/null 2>&1; then
          wallpaper_notify_emit "${HYPR_WALLPAPER_NOTIFY_NAME:-}" "${HYPR_WALLPAPER_NOTIFY_ICON:-}"
        fi
      fi
    } 202>&- &

    if [[ -n "${wallList[setIndex]:-}" ]] && [[ -z "${wallHash[setIndex]:-}" ]]; then
      wallHash[setIndex]="$(set_hash "${wallList[setIndex]}")"
    fi

    if [[ -n "${wallHash[setIndex]:-}" ]]; then
      ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.sqre" "${current_square_thumbnail_link}"
      ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.thmb" "${current_thumbnail_link}"
      ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.blur" "${current_blur_thumbnail_link}"
      ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.quad" "${current_quad_thumbnail_link}"
    else
      print_log -warn "wallpaper" "missing hash for ${wallList[setIndex]:-unknown}"
    fi

    rm -f "${WALLPAPER_CURRENT_DIR}/wall.fit"
  fi
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
  fi

  apply_selected_wallpaper "${wallList[setIndex]}"
}
