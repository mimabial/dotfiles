#!/usr/bin/env bash

# shellcheck disable=SC1091
source "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh"
export WALLPAPER_THUMB_DIR

cacheIn=""
mode=""
wall_inputs=()
invalid_inputs=0

setup_cache_lock() {
  WALLPAPER_CACHE_LOCK="$(hypr_lock_path wallpaper_cache)"
  exec 204>"${WALLPAPER_CACHE_LOCK}"
  if ! flock -n 204; then
    flock 204
  fi
  trap 'flock -u 204 2>/dev/null' EXIT
}

prepare_cache_dirs() {
  [[ -d "${HYPR_THEME_DIR}" ]] && cacheIn="${HYPR_THEME_DIR}" || exit 1
  [[ -d "${WALLPAPER_THUMB_DIR}" ]] || mkdir -p "${WALLPAPER_THUMB_DIR}"
  [[ -d "${HYPR_CACHE_HOME}/landing" ]] || mkdir -p "${HYPR_CACHE_HOME}/landing"
  [[ -d "${HYPR_CACHE_HOME}/wal" ]] || mkdir -p "${HYPR_CACHE_HOME}/wal"
}

resolve_cache_limits() {
  local cores mem_avail_kb mem_avail_mb
  local reserve_mb per_job_mb mem_budget_mb jobs_by_mem jobs_default cache_jobs
  local magick_mem_mb magick_map_mb magick_threads

  cores="$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  [[ "${cores}" =~ ^[0-9]+$ ]] || cores=1

  mem_avail_kb="$(awk '/MemAvailable/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  if [[ -z "${mem_avail_kb}" ]]; then
    mem_avail_kb="$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  fi
  [[ "${mem_avail_kb}" =~ ^[0-9]+$ ]] || mem_avail_kb=0
  mem_avail_mb=$((mem_avail_kb / 1024))

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
  local x_hash="$1"
  local x_wall="$2"
  local force="$3"
  local temp_image=""

  if ! wallpaper_is_video "${x_wall}"; then
    printf '%s\n' "${x_wall}"
    return 0
  fi

  if [[ "${force}" -ne 1 ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${x_hash}.thmb" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${x_hash}.sqre" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${x_hash}.blur" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${x_hash}.quad" ]]; then
    printf '%s\n' "${x_wall}"
    return 0
  fi

  temp_image="${TMPDIR:-/tmp}/${x_hash}.png"
  if [[ "${force}" -ne 1 ]]; then
    send_ephemeral_notif "hypr-wallpaper-cache" -a "Wallpaper cache" -t 2000 "Extracting thumbnail from video wallpaper..."
  fi
  extract_thumbnail "${x_wall}" "${temp_image}"
  printf '%s\n' "${temp_image}"
}

square_thumb_path() {
  printf '%s/%s.sqre' "${WALLPAPER_THUMB_DIR}" "$1"
}

write_main_thumb() {
  local x_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")
  local tmp_thmb="${WALLPAPER_THUMB_DIR}/.${x_hash}.thmb"

  magick "${magick_args[@]}" "${source_image}"[0] -strip -resize 1000 -gravity center -extent 1000 -quality 90 "${tmp_thmb}" &&
    mv -f "${tmp_thmb}" "${WALLPAPER_THUMB_DIR}/${x_hash}.thmb" || rm -f "${tmp_thmb}"
}

write_square_thumb() {
  local x_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")

  magick "${magick_args[@]}" "${source_image}"[0] -strip -thumbnail 500x500^ -gravity center -extent 500x500 "${WALLPAPER_THUMB_DIR}/${x_hash}.sqre.png" &&
    mv "${WALLPAPER_THUMB_DIR}/${x_hash}.sqre.png" "$(square_thumb_path "${x_hash}")"
}

write_blur_thumb() {
  local x_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")
  local tmp_blur="${WALLPAPER_THUMB_DIR}/.${x_hash}.blur"

  magick "${magick_args[@]}" "${source_image}"[0] -strip -scale 10% -blur 0x3 -resize 100% "${tmp_blur}" &&
    mv -f "${tmp_blur}" "${WALLPAPER_THUMB_DIR}/${x_hash}.blur" || rm -f "${tmp_blur}"
}

write_quad_thumb() {
  local x_hash="$1"
  local style="$2"
  shift 2
  local -a magick_args=("$@")

  if [[ "${style}" == "force" ]]; then
    magick "${magick_args[@]}" "$(square_thumb_path "${x_hash}")" \
      \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "polygon 400,500 500,500 500,0 450,0" -fill black -draw "polygon 500,500 500,0 450,500" \) \
      -alpha Off -compose CopyOpacity -composite "${WALLPAPER_THUMB_DIR}/${x_hash}.quad.png" &&
      mv "${WALLPAPER_THUMB_DIR}/${x_hash}.quad.png" "${WALLPAPER_THUMB_DIR}/${x_hash}.quad"
    return 0
  fi

  magick "${magick_args[@]}" "$(square_thumb_path "${x_hash}")" \
    \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "rectangle 400,0 500,500" -fill black -draw "rectangle 450,0 500,500" \) \
    -alpha Off -compose CopyOpacity -composite "${WALLPAPER_THUMB_DIR}/${x_hash}.quad.png" &&
    mv "${WALLPAPER_THUMB_DIR}/${x_hash}.quad.png" "${WALLPAPER_THUMB_DIR}/${x_hash}.quad"
}

cache_missing_outputs() {
  local x_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")

  if [ ! -e "${WALLPAPER_THUMB_DIR}/${x_hash}.thmb" ]; then
    write_main_thumb "${x_hash}" "${source_image}" "${magick_args[@]}"
  fi
  if [ ! -e "$(square_thumb_path "${x_hash}")" ]; then
    write_square_thumb "${x_hash}" "${source_image}" "${magick_args[@]}"
  fi
  if [ ! -e "${WALLPAPER_THUMB_DIR}/${x_hash}.blur" ]; then
    write_blur_thumb "${x_hash}" "${source_image}" "${magick_args[@]}"
  fi
  if [ ! -e "${WALLPAPER_THUMB_DIR}/${x_hash}.quad" ]; then
    write_quad_thumb "${x_hash}" "normal" "${magick_args[@]}"
  fi
}

cache_all_outputs() {
  local x_hash="$1"
  local source_image="$2"
  local -a magick_args=("$@")
  magick_args=("${magick_args[@]:2}")

  write_main_thumb "${x_hash}" "${source_image}" "${magick_args[@]}"
  write_square_thumb "${x_hash}" "${source_image}" "${magick_args[@]}"
  write_blur_thumb "${x_hash}" "${source_image}" "${magick_args[@]}"
  write_quad_thumb "${x_hash}" "force" "${magick_args[@]}"
}

build_wallcache() {
  local x_hash="$1"
  local x_wall="$2"
  local force="${3:-0}"
  local source_image="" temp_image=""
  local -a magick_args=()

  mapfile -d '' -t magick_args < <(magick_limit_args)
  source_image="$(ensure_video_still_frame "${x_hash}" "${x_wall}" "${force}")"
  [[ "${source_image}" == "${x_wall}" ]] || temp_image="${source_image}"

  if [[ "${force}" -eq 1 ]]; then
    cache_all_outputs "${x_hash}" "${source_image}" "${magick_args[@]}"
  else
    cache_missing_outputs "${x_hash}" "${source_image}" "${magick_args[@]}"
  fi

  [[ -n "${temp_image}" ]] && rm -f "${temp_image}"
}

fn_wallcache() {
  build_wallcache "$1" "$2" 0
}

fn_wallcache_force() {
  build_wallcache "$1" "$2" 1
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
        cacheIn="$(dirname "${HYPR_THEME_DIR}")/${OPTARG}"
        if [ ! -d "${cacheIn}" ]; then
          echo "Error: Input theme \"${OPTARG}\" not found!"
          exit 1
        fi
        ;;
      f)
        cacheIn="$(dirname "${HYPR_THEME_DIR}")"
        mode="_force"
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
  wallHash=()
  wallList=()

  for wall_input in "${wall_inputs[@]}"; do
    wallHash+=("$("${HYPR_HASH_COMMAND:-sha1sum}" "${wall_input}" | awk '{print $1}')")
    wallList+=("${wall_input}")
  done
}

load_catalog_wallpapers() {
  wallPathArray=("${cacheIn}")
  wallPathArray+=("${WALLPAPER_CUSTOM_PATHS[@]}")
  get_hashmap "${wallPathArray[@]}" --no-notify
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
  [[ ${#wallList[@]} -eq 0 ]] && exit 0
  parallel --bar --link --jobs "${WALLPAPER_CACHE_JOBS}" "fn_wallcache${mode}" ::: "${wallHash[@]}" ::: "${wallList[@]}"
}

main() {
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

export -f fn_wallcache fn_wallcache_force extract_thumbnail
main "$@"
