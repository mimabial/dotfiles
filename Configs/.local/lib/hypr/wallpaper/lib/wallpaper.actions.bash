#!/usr/bin/env bash

# Apply/set wallpaper links and trigger cache/color pipelines.

Wall_Cache() {
  local apply_colors=1

  if [[ "${WALLPAPER_SKIP_COLORS:-0}" -eq 1 ]] || [[ "${enableWallDcol:-1}" -eq 0 ]]; then
    apply_colors=0
  fi

  # Experimental, set to 1 if stable
  if [[ "${WALLPAPER_RELOAD_ALL:-1}" -eq 1 ]] && [[ ${wallpaper_setter_flag} != "link" ]]; then
    print_log -sec "wallpaper" "Reloading themes and wallpapers"
    export reload_flag=1
  fi

  ln -fs "${wallList[setIndex]}" "${wallSet}"
  ln -fs "${wallList[setIndex]}" "${wallCur}"

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
      fi
    } 202>&- &

    if [[ -n "${wallList[setIndex]:-}" ]] && [[ -z "${wallHash[setIndex]:-}" ]]; then
      wallHash[setIndex]="$(set_hash "${wallList[setIndex]}")"
    fi

    if [[ -n "${wallHash[setIndex]:-}" ]]; then
      ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.sqre" "${wallSqr}"
      ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.thmb" "${wallTmb}"
      ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.blur" "${wallBlr}"
      ln -fs "${WALLPAPER_THUMB_DIR}/${wallHash[setIndex]}.quad" "${wallQad}"
    else
      print_log -warn "wallpaper" "missing hash for ${wallList[setIndex]:-unknown}"
    fi

    rm -f "${WALLPAPER_CURRENT_DIR}/wall.fit"
  fi

  Wall_Auto_Prune
}

Wall_Change() {
  local curWall found
  found=false
  curWall="$(wallpaper_resolve_path "${wallSet}")"

  for i in "${!wallList[@]}"; do
    if [[ "${curWall}" == "${wallList[i]}" ]]; then
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

  Wall_Cache "${wallList[setIndex]}"
}
