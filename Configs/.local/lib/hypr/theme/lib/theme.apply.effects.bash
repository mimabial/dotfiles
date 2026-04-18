#!/usr/bin/env bash

# Post-apply helpers owned by theme.apply.sh.

theme_apply_sync_backend_wallpaper_links() {
  local file=""
  local base=""

  [[ -d "${WALLPAPER_CURRENT_DIR}" ]] || return 0

  while IFS= read -r -d '' file; do
    base="$(basename "${file}" .png)"
    pkg_installed "${base}" || continue
    "${LIB_DIR}/hypr/wallpaper.sh" link --backend "${base}" >/dev/null 2>&1 || true
  done < <(find -H "${WALLPAPER_CURRENT_DIR}" -maxdepth 1 -type l -name "*.png" -print0)
}

theme_apply_sync_nvim_theme() {
  if [[ -x "${HYPR_LIB_DIR}/util/nvim-theme-sync.sh" ]]; then
    "${HYPR_LIB_DIR}/util/nvim-theme-sync.sh" >/dev/null 2>&1 || true
  fi
}

theme_apply_thumbs_precache() {
  local -a cache_args=()
  local wall=""
  local queue_script=""
  local cache_script=""

  if [[ ${#thmWall[@]} -eq 0 ]]; then
    get_themes
  fi

  for wall in "${thmWall[@]}"; do
    [[ -n "${wall}" ]] || continue
    [[ -r "${wall}" ]] || continue
    cache_args+=(-w "${wall}")
  done

  queue_script="${LIB_DIR}/hypr/wallpaper/wallcache.daemon.sh"
  cache_script="${LIB_DIR}/hypr/wallpaper/awww-wallcache.sh"
  [[ -x "${queue_script}" || -x "${cache_script}" ]] || return 0
  [[ ${#cache_args[@]} -eq 0 ]] && return 0

  if [[ -x "${queue_script}" ]]; then
    "${queue_script}" --enqueue "${cache_args[@]}" &>/dev/null &
  else
    "${cache_script}" "${cache_args[@]}" &>/dev/null &
  fi
}

theme_apply_colors_precache() {
  local queue_script=""
  local current_index=-1
  local next_index=-1
  local prev_index=-1
  local current_theme="${HYPR_THEME}"
  local i=""
  declare -a precache_themes=()

  [[ "${selected_color_mode:-0}" -eq 0 ]] || return 0

  queue_script="${LIB_DIR}/hypr/theme/theme.precache.sh"
  [[ -x "${queue_script}" ]] || return 0

  if [[ ${#thmList[@]} -eq 0 ]]; then
    get_themes
  fi
  [[ ${#thmList[@]} -gt 1 ]] || return 0

  for i in "${!thmList[@]}"; do
    if [[ "${thmList[i]}" == "${current_theme}" ]]; then
      current_index="${i}"
      break
    fi
  done
  [[ "${current_index}" -ge 0 ]] || return 0

  next_index=$(((current_index + 1) % ${#thmList[@]}))
  prev_index=$((current_index - 1))
  [[ "${prev_index}" -lt 0 ]] && prev_index=$((${#thmList[@]} - 1))

  [[ "${thmList[next_index]}" != "${current_theme}" ]] && precache_themes+=("${thmList[next_index]}")
  if [[ "${prev_index}" -ne "${next_index}" ]] && [[ "${thmList[prev_index]}" != "${current_theme}" ]]; then
    precache_themes+=("${thmList[prev_index]}")
  fi

  [[ ${#precache_themes[@]} -gt 0 ]] || return 0
  "${queue_script}" "${precache_themes[@]}" &>/dev/null &
}

theme_apply_run_post_effects() {
  theme_apply_sync_backend_wallpaper_links
  theme_apply_sync_nvim_theme
  theme_apply_thumbs_precache
  theme_apply_colors_precache
}
