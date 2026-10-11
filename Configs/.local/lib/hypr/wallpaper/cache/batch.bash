#!/usr/bin/env bash

wallcache_acquire_lock() {
  WALLPAPER_CACHE_LOCK="$(hypr_lock_path_ensure_parent wallpaper_cache)"
  exec {wallpaper_cache_lock_fd}>"${WALLPAPER_CACHE_LOCK}"
  flock "${wallpaper_cache_lock_fd}"
  trap 'wallcache_release_lock "$?"' EXIT
}

wallcache_release_lock() {
  local exit_code="${1:-$?}"
  flock -u "${wallpaper_cache_lock_fd}" 2>/dev/null || true
  return "${exit_code}"
}

wallcache_prepare_directories() {
  [[ -d "${HYPR_THEME_DIR}" ]] && wallcache_source_dir="${HYPR_THEME_DIR}" || exit 1
  [[ -d "${WALLPAPER_THUMB_DIR}" ]] || mkdir -p "${WALLPAPER_THUMB_DIR}"
  [[ -d "${HYPR_CACHE_HOME}/landing" ]] || mkdir -p "${HYPR_CACHE_HOME}/landing"
}

WALLCACHE_DEFAULT_RESERVE_MB=2048
WALLCACHE_DEFAULT_JOB_MB=1200

wallcache_environment_count() {
  local value="${!1:-}"
  [[ "${value}" =~ ^[0-9]+$ ]] && printf '%s\n' "${value}" || printf '%s\n' "$2"
}

wallcache_job_count() {
  local cores="$1" mem_avail_mb="$2"
  local reserve_mb per_job_mb mem_budget_mb jobs_by_mem

  reserve_mb="$(wallcache_environment_count WALLPAPER_CACHE_RESERVE_MB "${WALLCACHE_DEFAULT_RESERVE_MB}")"
  per_job_mb="$(wallcache_environment_count WALLPAPER_CACHE_JOB_MB "${WALLCACHE_DEFAULT_JOB_MB}")"
  ((per_job_mb > 0)) || per_job_mb="${WALLCACHE_DEFAULT_JOB_MB}"
  mem_budget_mb=$((mem_avail_mb - reserve_mb))
  if (( mem_budget_mb < per_job_mb )); then
    jobs_by_mem=1
  else
    jobs_by_mem=$((mem_budget_mb / per_job_mb))
  fi
  (( jobs_by_mem < 1 )) && jobs_by_mem=1

  if [[ "${WALLPAPER_CACHE_JOBS:-}" =~ ^[0-9]+$ ]] && (( WALLPAPER_CACHE_JOBS > 0 )); then
    printf '%s\n' "${WALLPAPER_CACHE_JOBS}"
  elif (( jobs_by_mem < cores )); then
    printf '%s\n' "${jobs_by_mem}"
  else
    printf '%s\n' "${cores}"
  fi
}

wallcache_resolve_resource_limits() {
  local cores=0 mem_avail_mb=0

  hypr_read_host_capacity cores mem_avail_mb
  WALLPAPER_CACHE_JOBS="$(wallcache_job_count "${cores}" "${mem_avail_mb}")"
  export WALLPAPER_CACHE_JOBS
  hypr_export_magick_limits "${cores}" "${mem_avail_mb}"
}

wallcache_link_shared_rofi_themes() {
  local xdg_data_home="" src_dir="" dst_dir=""
  local -a theme_files=()

  command -v rofi &>/dev/null || return 0
  [[ "${XDG_DATA_DIRS:-}" =~ share/hypr ]] && return 0

  xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  src_dir="${xdg_data_home}/hypr/rofi/themes"
  dst_dir="${xdg_data_home}/rofi/themes"
  [[ -d "${src_dir}" ]] || return 0

  mkdir -p "${dst_dir}"
  shopt -s nullglob
  theme_files=("${src_dir}"/*)
  shopt -u nullglob
  ((${#theme_files[@]} > 0)) || return 0
  ln -snf "${theme_files[@]}" "${dst_dir}/"
}

wallcache_parse_arguments() {
  while getopts "w:t:f" option; do
    case "${option}" in
      w)
        if [[ -z "${OPTARG}" ]] || [[ ! -f "${OPTARG}" ]]; then
          echo "Error: Input wallpaper \"${OPTARG}\" not found!" >&2
          wallcache_has_invalid_inputs=1
          continue
        fi
        wallcache_requested_paths+=("$(realpath "${OPTARG}")")
        ;;
      t)
        wallcache_source_dir="${HYPR_THEME_DIR%/*}/${OPTARG}"
        if [ ! -d "${wallcache_source_dir}" ]; then
          echo "Error: Input theme \"${OPTARG}\" not found!"
          exit 1
        fi
        ;;
      f)
        wallcache_source_dir="${HYPR_THEME_DIR%/*}"
        wallcache_worker_flag="--build_force"
        ;;
      *)
        echo "... invalid option ..."
        echo "hyprshell wallpaper/wallpaper.cache -[option]"
        echo "w : generate cache for input wallpaper"
        echo "t : generate cache for input theme"
        echo "f : full cache rebuild"
        exit 1
        ;;
    esac
  done
}

wallcache_load_requested_wallpapers() {
  local wall_input="" wall_hash=""
  wallpaper_hashes=()
  wallpaper_paths=()

  for wall_input in "${wallcache_requested_paths[@]}"; do
    read -r wall_hash _ < <("${HYPR_HASH_COMMAND}" "${wall_input}") || :
    wallpaper_hashes+=("${wall_hash}")
    wallpaper_paths+=("${wall_input}")
  done
}

wallcache_scan_source_directories() {
  wallcache_source_paths=("${wallcache_source_dir}" "${WALLPAPER_CUSTOM_PATHS[@]}")
  wallpaper_scan_hashes_into wallpaper_hashes wallpaper_paths "${wallcache_source_paths[@]}"
}

wallcache_load_targets() {
  if [[ ${#wallcache_requested_paths[@]} -gt 0 ]]; then
    wallcache_load_requested_wallpapers
  else
    wallcache_scan_source_directories
  fi
}

wallcache_log_resource_limits() {
  if [[ "${LOG_LEVEL:-}" == "debug" ]]; then
    print_log -sec "wallpaper" -stat "cache" "jobs=${WALLPAPER_CACHE_JOBS} mem=${WALLPAPER_MAGICK_MEM_MB}MiB map=${WALLPAPER_MAGICK_MAP_MB}MiB threads=${WALLPAPER_MAGICK_THREADS}"
  fi
}

wallcache_run_parallel_jobs() {
  local script_path="${HYPR_LIB_DIR}/wallpaper/wallpaper.cache.sh"
  [[ ${#wallpaper_paths[@]} -eq 0 ]] && exit 0
  parallel --bar --link --jobs "${WALLPAPER_CACHE_JOBS}" \
    "${script_path}" "${wallcache_worker_flag}" '{1}' '{2}' ::: "${wallpaper_hashes[@]}" ::: "${wallpaper_paths[@]}"
}
