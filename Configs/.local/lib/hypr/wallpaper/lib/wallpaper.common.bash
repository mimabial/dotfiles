#!/usr/bin/env bash

# Shared helper functions for wallpaper modules.

run_low_prio() {
  local nice_level="${WALLPAPER_NICE_LEVEL:-10}"
  [[ "${nice_level}" =~ ^-?[0-9]+$ ]] || nice_level=10

  if command -v ionice &>/dev/null; then
    ionice -c 3 nice -n "${nice_level}" "$@"
  else
    nice -n "${nice_level}" "$@"
  fi
}

wallpaper_cache_root() {
  local cache_root="${WALLPAPER_CACHE_DIR}"
  [[ -z "${cache_root}" ]] && cache_root="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}/wallpaper"
  printf '%s\n' "${cache_root}"
}

wallpaper_resolve_path() {
  local input_path="${1}"
  readlink -f -- "${input_path}" 2>/dev/null \
    || realpath -- "${input_path}" 2>/dev/null \
    || printf '%s' "${input_path}"
}

wallpaper_supported_files_array() {
  local out_name="${1}"
  local -n out_ref="${out_name}"

  out_ref=("gif" "jpg" "jpeg" "png" "${WALLPAPER_FILETYPES[@]}")
  if [[ ${#WALLPAPER_OVERRIDE_FILETYPES[@]} -gt 0 ]]; then
    out_ref=("${WALLPAPER_OVERRIDE_FILETYPES[@]}")
  fi
}

wallpaper_extensions_regex() {
  local -a extensions=("$@")
  local regex_ext=""
  local ext

  for ext in "${extensions[@]}"; do
    [[ -n "${ext}" ]] || continue
    if [[ -z "${regex_ext}" ]]; then
      regex_ext="${ext}"
    else
      regex_ext="${regex_ext}|${ext}"
    fi
  done

  [[ -z "${regex_ext}" ]] && regex_ext="gif|jpg|jpeg|png"
  printf '%s\n' "${regex_ext}"
}

wallpaper_theme_sources() {
  wallPathArray=()
  [[ -d "${HYPR_THEME_DIR}" ]] || return 1

  if [[ -d "${HYPR_THEME_DIR}/wallpapers" ]]; then
    wallPathArray=("${HYPR_THEME_DIR}/wallpapers")
  elif [[ -d "${HYPR_THEME_DIR}/wallpaper" ]]; then
    wallPathArray=("${HYPR_THEME_DIR}/wallpaper")
  else
    wallPathArray=("${HYPR_THEME_DIR}")
  fi

  wallPathArray+=("${WALLPAPER_CUSTOM_PATHS[@]}")
}

wallpaper_queue_script() {
  local lib_dir="${LIB_DIR}"
  [[ -z "${lib_dir}" ]] && lib_dir="${HOME}/.local/lib"
  printf '%s\n' "${lib_dir}/hypr/wallpaper/wallcache.daemon.sh"
}

wallpaper_cache_script() {
  local lib_dir="${LIB_DIR}"
  [[ -z "${lib_dir}" ]] && lib_dir="${HOME}/.local/lib"
  printf '%s\n' "${lib_dir}/hypr/wallpaper/swwwallcache.sh"
}

wallpaper_enqueue_cache_jobs() {
  local run_in_background=0
  if [[ "${1:-}" == "--background" ]]; then
    run_in_background=1
    shift
  fi

  [[ $# -gt 0 ]] || return 1

  local queue_script=""
  local cache_script=""
  queue_script="$(wallpaper_queue_script)"
  cache_script="$(wallpaper_cache_script)"

  if [[ -x "${queue_script}" ]]; then
    if [[ "${run_in_background}" -eq 1 ]]; then
      run_low_prio "${queue_script}" --enqueue "$@" &>/dev/null &
    else
      run_low_prio "${queue_script}" --enqueue "$@" &>/dev/null
    fi
    return 0
  fi

  if [[ -x "${cache_script}" ]]; then
    if [[ "${run_in_background}" -eq 1 ]]; then
      run_low_prio "${cache_script}" "$@" &>/dev/null &
    else
      run_low_prio "${cache_script}" "$@" &>/dev/null
    fi
    return 0
  fi

  return 1
}
