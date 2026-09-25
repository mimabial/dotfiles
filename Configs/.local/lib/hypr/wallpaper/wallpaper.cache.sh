#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell wallpaper/wallpaper.cache [-w WALLPAPER] [-t THEME] [-f]
Generate wallpaper thumbnail/blur caches: -w a single image, -t one theme,
-f every theme (rebuilding entries that already exist)." "$@"

hypr_runtime_require state wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1
export WALLPAPER_THUMB_DIR

cache_source_dir=""
cache_build_mode=""
wall_inputs=()
declare -a wallpaper_hashes=() wallpaper_paths=() wallpaper_sources=()
invalid_inputs=0

setup_cache_lock() {
  WALLPAPER_CACHE_LOCK="$(hypr_lock_path wallpaper_cache)"
  exec {wallpaper_cache_lock_fd}>"${WALLPAPER_CACHE_LOCK}"
  flock "${wallpaper_cache_lock_fd}"
  trap 'wallcache_release_lock "$?"' EXIT
}

wallcache_release_lock() {
  local exit_code="${1:-$?}"
  flock -u "${wallpaper_cache_lock_fd}" 2>/dev/null || true
  return "${exit_code}"
}

prepare_cache_dirs() {
  [[ -d "${HYPR_THEME_DIR}" ]] && cache_source_dir="${HYPR_THEME_DIR}" || exit 1
  [[ -d "${WALLPAPER_THUMB_DIR}" ]] || mkdir -p "${WALLPAPER_THUMB_DIR}"
  [[ -d "${HYPR_CACHE_HOME}/landing" ]] || mkdir -p "${HYPR_CACHE_HOME}/landing"
  [[ -d "${HYPR_CACHE_HOME}/wal" ]] || mkdir -p "${HYPR_CACHE_HOME}/wal"
}

resolve_cache_limits() {
  local cores mem_avail_kb mem_avail_mb
  local reserve_mb per_job_mb mem_budget_mb jobs_by_mem jobs_default cache_jobs
  local magick_mem_mb magick_map_mb magick_threads

  hypr_read_host_capacity

  reserve_mb="${WALLPAPER_CACHE_RESERVE_MB:-2048}"
  per_job_mb="${WALLPAPER_CACHE_JOB_MB:-1200}"
  [[ "${reserve_mb}" =~ ^[0-9]+$ ]] || reserve_mb=2048
  [[ "${per_job_mb}" =~ ^[0-9]+$ ]] || per_job_mb=1200

  mem_budget_mb=$((mem_avail_mb - reserve_mb))
  if (( mem_budget_mb < per_job_mb )); then
    jobs_by_mem=1
  else
    jobs_by_mem=$((mem_budget_mb / per_job_mb))
  fi
  (( jobs_by_mem < 1 )) && jobs_by_mem=1

  jobs_default=$cores
  (( jobs_by_mem < jobs_default )) && jobs_default=$jobs_by_mem
  cache_jobs="${jobs_default}"
  if [[ "${WALLPAPER_CACHE_JOBS:-}" =~ ^[0-9]+$ ]] && (( WALLPAPER_CACHE_JOBS > 0 )); then
    cache_jobs="${WALLPAPER_CACHE_JOBS}"
  fi

  magick_mem_mb="${WALLPAPER_MAGICK_MEM_MB:-}"
  [[ "${magick_mem_mb}" =~ ^[0-9]+$ ]] || magick_mem_mb=""
  if [[ -z "${magick_mem_mb}" ]]; then
    if (( mem_avail_mb > 0 )); then
      magick_mem_mb=$((mem_avail_mb / 8))
      (( magick_mem_mb < 256 )) && magick_mem_mb=256
      (( magick_mem_mb > 1024 )) && magick_mem_mb=1024
    else
      magick_mem_mb=512
    fi
  fi

  magick_map_mb="${WALLPAPER_MAGICK_MAP_MB:-}"
  [[ "${magick_map_mb}" =~ ^[0-9]+$ ]] || magick_map_mb=""
  if [[ -z "${magick_map_mb}" ]]; then
    magick_map_mb=$((magick_mem_mb * 2))
    (( magick_map_mb < 512 )) && magick_map_mb=512
    (( magick_map_mb > 4096 )) && magick_map_mb=4096
  fi

  magick_threads="${WALLPAPER_MAGICK_THREADS:-}"
  [[ "${magick_threads}" =~ ^[0-9]+$ ]] || magick_threads=""
  if [[ -z "${magick_threads}" ]]; then
    if (( cores > 4 )); then
      magick_threads=4
    elif (( cores > 0 )); then
      magick_threads="${cores}"
    else
      magick_threads=1
    fi
  fi

  export WALLPAPER_CACHE_JOBS="${cache_jobs}"
  export WALLPAPER_MAGICK_MEM_MB="${magick_mem_mb}"
  export WALLPAPER_MAGICK_MAP_MB="${magick_map_mb}"
  export WALLPAPER_MAGICK_THREADS="${magick_threads}"
}

magick_limit_args() {
  local -a args=()
  [[ -n "${WALLPAPER_MAGICK_MEM_MB:-}" ]] && args+=(-limit memory "${WALLPAPER_MAGICK_MEM_MB}MiB")
  [[ -n "${WALLPAPER_MAGICK_MAP_MB:-}" ]] && args+=(-limit map "${WALLPAPER_MAGICK_MAP_MB}MiB")
  [[ -n "${WALLPAPER_MAGICK_THREADS:-}" ]] && args+=(-limit thread "${WALLPAPER_MAGICK_THREADS}")
  printf '%s\0' "${args[@]}"
}

wallpaper_is_video() {
  file --mime-type -b "$1" | grep -q '^video/'
}

ensure_video_still_frame() {
  local wallpaper_hash="$1"
  local wallpaper_path="$2"
  local force="$3"
  local temp_image=""

  if ! wallpaper_is_video "${wallpaper_path}"; then
    printf '%s\n' "${wallpaper_path}"
    return 0
  fi

  if [[ "${force}" -ne 1 ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.thmb" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.sqre" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.blur" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad" ]]; then
    printf '%s\n' "${wallpaper_path}"
    return 0
  fi

  temp_image="${TMPDIR:-/tmp}/${wallpaper_hash}.png"
  if [[ "${force}" -ne 1 ]]; then
    send_ephemeral_notif "hypr-wallpaper-cache" -a "Wallpaper cache" -t 2000 "Extracting thumbnail from video wallpaper..."
  fi
  extract_thumbnail "${wallpaper_path}" "${temp_image}"
  printf '%s\n' "${temp_image}"
}

square_thumb_path() {
  printf '%s/%s.sqre' "${WALLPAPER_THUMB_DIR}" "$1"
}

write_main_thumb() {
  local wallpaper_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")
  local temporary_thumbnail="${WALLPAPER_THUMB_DIR}/.${wallpaper_hash}.thmb.png"

  { magick "${magick_args[@]}" "${source_image}"[0] -strip -resize 1000 -gravity center -extent 1000 -quality 90 "png:${temporary_thumbnail}" &&
    mv -f "${temporary_thumbnail}" "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.thmb"; } || {
    rm -f "${temporary_thumbnail}"
    return 1
  }
}

write_square_thumb() {
  local wallpaper_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")

  magick "${magick_args[@]}" "${source_image}"[0] -strip -thumbnail 500x500^ -gravity center -extent 500x500 "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.sqre.png" &&
    mv "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.sqre.png" "$(square_thumb_path "${wallpaper_hash}")"
}

write_blur_thumb() {
  local wallpaper_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")
  local temporary_blur="${WALLPAPER_THUMB_DIR}/.${wallpaper_hash}.blur.png"

  { magick "${magick_args[@]}" "${source_image}"[0] -strip -scale 10% -blur 0x3 -resize 100% "png:${temporary_blur}" &&
    mv -f "${temporary_blur}" "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.blur"; } || {
    rm -f "${temporary_blur}"
    return 1
  }
}

write_quad_thumb() {
  local wallpaper_hash="$1"
  local style="$2"
  shift 2
  local -a magick_args=("$@")

  if [[ "${style}" == "force" ]]; then
    magick "${magick_args[@]}" "$(square_thumb_path "${wallpaper_hash}")" \
      \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "polygon 400,500 500,500 500,0 450,0" -fill black -draw "polygon 500,500 500,0 450,500" \) \
      -alpha Off -compose CopyOpacity -composite "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad.png" &&
      mv "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad.png" "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad"
    return 0
  fi

  magick "${magick_args[@]}" "$(square_thumb_path "${wallpaper_hash}")" \
    \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "rectangle 400,0 500,500" -fill black -draw "rectangle 450,0 500,500" \) \
    -alpha Off -compose CopyOpacity -composite "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad.png" &&
    mv "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad.png" "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad"
}

cache_missing_outputs() {
  local wallpaper_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")

  if [ ! -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.thmb" ]; then
    write_main_thumb "${wallpaper_hash}" "${source_image}" "${magick_args[@]}"
  fi
  if [ ! -e "$(square_thumb_path "${wallpaper_hash}")" ]; then
    write_square_thumb "${wallpaper_hash}" "${source_image}" "${magick_args[@]}"
  fi
  if [ ! -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.blur" ]; then
    write_blur_thumb "${wallpaper_hash}" "${source_image}" "${magick_args[@]}"
  fi
  if [ ! -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad" ]; then
    write_quad_thumb "${wallpaper_hash}" "normal" "${magick_args[@]}"
  fi
}

cache_all_outputs() {
  local wallpaper_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")

  write_main_thumb "${wallpaper_hash}" "${source_image}" "${magick_args[@]}"
  write_square_thumb "${wallpaper_hash}" "${source_image}" "${magick_args[@]}"
  write_blur_thumb "${wallpaper_hash}" "${source_image}" "${magick_args[@]}"
  write_quad_thumb "${wallpaper_hash}" "force" "${magick_args[@]}"
}

build_wallcache() {
  local wallpaper_hash="$1"
  local wallpaper_path="$2"
  local force="${3:-0}"
  local source_image="" temp_image=""
  local -a magick_args=()

  mapfile -d '' -t magick_args < <(magick_limit_args)
  source_image="$(ensure_video_still_frame "${wallpaper_hash}" "${wallpaper_path}" "${force}")"
  [[ "${source_image}" == "${wallpaper_path}" ]] || temp_image="${source_image}"

  if [[ "${force}" -eq 1 ]]; then
    cache_all_outputs "${wallpaper_hash}" "${source_image}" "${magick_args[@]}"
  else
    cache_missing_outputs "${wallpaper_hash}" "${source_image}" "${magick_args[@]}"
  fi

  [[ -n "${temp_image}" ]] && rm -f "${temp_image}"
  return 0
}

link_rofi_themes() {
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

run_single_cache_job() {
  local worker_mode="${1:-}"
  local wall_hash="${2:-}"
  local wall_path="${3:-}"

  [[ -n "${wall_hash}" && -n "${wall_path}" ]] || return 1

  case "${worker_mode}" in
    _force) build_wallcache "${wall_hash}" "${wall_path}" 1 ;;
    "") build_wallcache "${wall_hash}" "${wall_path}" 0 ;;
    *) return 1 ;;
  esac
}

parse_options() {
  while getopts "w:t:f" option; do
    case "${option}" in
      w)
        if [[ -z "${OPTARG}" ]] || [[ ! -f "${OPTARG}" ]]; then
          echo "Error: Input wallpaper \"${OPTARG}\" not found!" >&2
          invalid_inputs=1
          continue
        fi
        wall_inputs+=("$(realpath "${OPTARG}")")
        ;;
      t)
        cache_source_dir="$(dirname "${HYPR_THEME_DIR}")/${OPTARG}"
        if [ ! -d "${cache_source_dir}" ]; then
          echo "Error: Input theme \"${OPTARG}\" not found!"
          exit 1
        fi
        ;;
      f)
        cache_source_dir="$(dirname "${HYPR_THEME_DIR}")"
        cache_build_mode="_force"
        ;;
      *)
        echo "... invalid option ..."
        echo "$(basename "${0}") -[option]"
        echo "w : generate cache for input wallpaper"
        echo "t : generate cache for input theme"
        echo "f : full cache rebuild"
        exit 1
        ;;
    esac
  done
}

load_explicit_wallpapers() {
  local wall_input=""
  wallpaper_hashes=()
  wallpaper_paths=()

  for wall_input in "${wall_inputs[@]}"; do
    wallpaper_hashes+=("$("${HYPR_HASH_COMMAND:-sha1sum}" "${wall_input}" | awk '{print $1}')")
    wallpaper_paths+=("${wall_input}")
  done
}

load_catalog_wallpapers() {
  wallpaper_sources=("${cache_source_dir}" "${WALLPAPER_CUSTOM_PATHS[@]}")
  wallpaper_scan_hashes_into wallpaper_hashes wallpaper_paths "${wallpaper_sources[@]}"
}

load_wallpaper_targets() {
  if [[ ${#wall_inputs[@]} -gt 0 ]]; then
    load_explicit_wallpapers
  else
    load_catalog_wallpapers
  fi
}

log_cache_limits() {
  if [[ "${LOG_LEVEL:-}" == "debug" ]]; then
    print_log -sec "wallpaper" -stat "cache" "jobs=${WALLPAPER_CACHE_JOBS} mem=${WALLPAPER_MAGICK_MEM_MB}MiB map=${WALLPAPER_MAGICK_MAP_MB}MiB threads=${WALLPAPER_MAGICK_THREADS}"
  fi
}

run_cache_jobs() {
  local script_path=""
  [[ ${#wallpaper_paths[@]} -eq 0 ]] && exit 0
  script_path="$(realpath "${BASH_SOURCE[0]}")" || exit 1
  parallel --bar --link --jobs "${WALLPAPER_CACHE_JOBS}" \
    "${script_path}" --build"${cache_build_mode}" '{1}' '{2}' ::: "${wallpaper_hashes[@]}" ::: "${wallpaper_paths[@]}"
}

dispatch_internal_job() {
  local mode_arg="${1:-}"
  shift || true
  case "${mode_arg}" in
    --build)
      run_single_cache_job "" "$@"
      ;;
    --build_force)
      run_single_cache_job "_force" "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

main() {
  if [[ "${1:-}" == --build* ]]; then
    dispatch_internal_job "$@"
    return $?
  fi

  setup_cache_lock
  prepare_cache_dirs
  parse_options "$@"

  if [[ ${#wall_inputs[@]} -eq 0 ]] && [[ "${invalid_inputs}" -eq 1 ]]; then
    exit 1
  fi

  link_rofi_themes
  resolve_cache_limits
  log_cache_limits
  load_wallpaper_targets
  run_cache_jobs
}

main "$@"
