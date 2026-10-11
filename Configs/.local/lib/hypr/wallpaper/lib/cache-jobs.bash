#!/usr/bin/env bash

wallpaper_enqueue_cache_jobs() {
  local run_in_background=0
  if [[ "${1:-}" == "--background" ]]; then
    run_in_background=1
    shift
  fi

  [[ $# -gt 0 ]] || return 1

  local queue_script="${HYPR_LIB_DIR}/wallpaper/wallcache.daemon.sh"
  local cache_script="${HYPR_LIB_DIR}/wallpaper/wallpaper.cache.sh"
  local -a job_command=()

  if [[ -x "${queue_script}" ]]; then
    job_command=("${queue_script}" --enqueue "$@")
  elif [[ -x "${cache_script}" ]]; then
    job_command=("${cache_script}" "$@")
  else
    return 1
  fi

  if [[ "${run_in_background}" -eq 1 ]]; then
    wallpaper_run_detached wallpaper_run_low_priority "${job_command[@]}" &>/dev/null
  else
    wallpaper_run_low_priority "${job_command[@]}" &>/dev/null
  fi
}

wallpaper_enqueue_missing_thumbnails() {
  local ext="${1}"
  [[ -z "${ext}" ]] && ext="sqre"

  local -a missing_walls=()
  local thumb hash wall

  for wall in "${wallpaper_paths[@]}"; do
    hash="${wallpaper_hash_by_path["${wall}"]:-}"
    if [[ -z "${hash}" ]]; then
      hash="$(wallpaper_file_hash "${wall}")"
      wallpaper_hash_by_path["${wall}"]="${hash}"
    fi
    [[ -n "${hash}" ]] || continue

    thumb="${WALLPAPER_THUMB_DIR}/${hash}.${ext}"
    [[ -e "${thumb}" ]] || missing_walls+=("${wall}")
  done

  if ((${#missing_walls[@]} > 0)); then
    local -a cache_args=()
    for wall in "${missing_walls[@]}"; do
      cache_args+=(-w "${wall}")
    done
    wallpaper_enqueue_cache_jobs --background "${cache_args[@]}" || true
  fi
}

wallpaper_enqueue_theme_thumbnails() {
  local theme_name="${HYPR_THEME}"

  [[ "${WALLPAPER_SKIP_PRECACHE:-0}" -eq 1 ]] && return 0
  [[ "${wallpaper_is_global}" == "true" ]] || return 0
  case "${wallpaper_action}" in
    "" | get | output | link) return 0 ;;
  esac
  [[ -n "${theme_name}" ]] || return 0

  local queue_script="${HYPR_LIB_DIR}/wallpaper/wallcache.daemon.sh"
  local cache_script="${HYPR_LIB_DIR}/wallpaper/wallpaper.cache.sh"

  if [[ -x "${queue_script}" ]]; then
    wallpaper_run_detached wallpaper_run_low_priority "${queue_script}" --enqueue -t "${theme_name}" &>/dev/null
    return 0
  fi

  if [[ -x "${cache_script}" ]]; then
    [[ "${WALLPAPER_PRECACHE_JOBS:-}" =~ ^[1-9][0-9]*$ ]] && local -x WALLPAPER_CACHE_JOBS="${WALLPAPER_PRECACHE_JOBS}"
    [[ "${WALLPAPER_PRECACHE_THREADS:-}" =~ ^[1-9][0-9]*$ ]] && local -x WALLPAPER_MAGICK_THREADS="${WALLPAPER_PRECACHE_THREADS}"
    wallpaper_run_detached wallpaper_run_low_priority "${cache_script}" -t "${theme_name}" &>/dev/null
  fi
}
