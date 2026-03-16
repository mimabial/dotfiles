#!/usr/bin/env bash

# Wallpaper precache helper for theme.switch.sh.

theme_thumbs_precache() {
  local -a cache_args=()
  local wall
  local lib_dir="${LIB_DIR}"
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

  [[ -z "${lib_dir}" ]] && lib_dir="${HOME}/.local/lib"
  queue_script="${lib_dir}/hypr/wallpaper/wallcache.daemon.sh"
  cache_script="${lib_dir}/hypr/wallpaper/swwwallcache.sh"
  [[ -x "${queue_script}" || -x "${cache_script}" ]] || return 0
  [[ ${#cache_args[@]} -eq 0 ]] && return 0

  if [[ -x "${queue_script}" ]]; then
    "${queue_script}" --enqueue "${cache_args[@]}" &>/dev/null &
  else
    "${cache_script}" "${cache_args[@]}" &>/dev/null &
  fi
}

theme_colors_precache() {
  local lib_dir="${LIB_DIR}"
  local queue_script=""
  local current_index=-1
  local next_index=-1
  local prev_index=-1
  local current_theme="${themeSet:-${HYPR_THEME}}"
  declare -a precache_themes=()

  [[ "${selected_color_mode:-0}" -eq 0 ]] || return 0

  [[ -z "${lib_dir}" ]] && lib_dir="${HOME}/.local/lib"
  queue_script="${lib_dir}/hypr/theme/theme.precache.sh"
  [[ -x "${queue_script}" ]] || return 0

  if [[ ${#thmList[@]} -eq 0 ]]; then
    get_themes
  fi
  [[ ${#thmList[@]} -gt 1 ]] || return 0

  local i
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
