#!/usr/bin/env bash

#// set variables

scrDir="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${scrDir}/globalcontrol.sh"
export scrDir
export thmbDir

# Lock file to prevent concurrent cache rebuilds
WALLPAPER_CACHE_LOCK="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-cache.lock"
exec 204>"${WALLPAPER_CACHE_LOCK}"
if ! flock -n 204; then
  flock 204
fi
trap 'flock -u 204 2>/dev/null' EXIT

# shellcheck disable=SC2154
[ -d "${HYPR_THEME_DIR}" ] && cacheIn="${HYPR_THEME_DIR}" || exit 1
[ -d "${thmbDir}" ] || mkdir -p "${thmbDir}"
# shellcheck disable=SC2154
[ -d "${cacheDir}/landing" ] || mkdir -p "${cacheDir}/landing"
[ -d "${cacheDir}/wal" ] || mkdir -p "${cacheDir}/wal"

# Adaptive cache limits (jobs + magick) with env overrides
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

#// define functions

# shellcheck disable=SC2317
fn_wallcache() {
  local x_hash="${1}"
  local x_wall="${2}"
  local is_video
  local tmp_thmb tmp_blur
  local -a magick_args=()

  [[ -n "${WALLPAPER_MAGICK_MEM_MB:-}" ]] && magick_args+=(-limit memory "${WALLPAPER_MAGICK_MEM_MB}MiB")
  [[ -n "${WALLPAPER_MAGICK_MAP_MB:-}" ]] && magick_args+=(-limit map "${WALLPAPER_MAGICK_MAP_MB}MiB")
  [[ -n "${WALLPAPER_MAGICK_THREADS:-}" ]] && magick_args+=(-limit thread "${WALLPAPER_MAGICK_THREADS}")

  is_video=$(file --mime-type -b "${x_wall}" | grep -c '^video/')

  if [ "${is_video}" -eq 1 ]; then
    if
      [ ! -e "${thmbDir}/${x_hash}.thmb" ] \
        || [ ! -e "${thmbDir}/${x_hash}.sqre" ] \
        || [ ! -e "${thmbDir}/${x_hash}.blur" ] \
        || [ ! -e "${thmbDir}/${x_hash}.quad" ]
    then
      local temp_image="/tmp/${x_hash}.png"
      notify-send -a "Wallpaper cache" "Extracting thumbnail from video wallpaper..."
      extract_thumbnail "${x_wall}" "${temp_image}"
      x_wall="${temp_image}"
    fi
  fi

  if [ ! -e "${thmbDir}/${x_hash}.thmb" ]; then
    tmp_thmb="${thmbDir}/.${x_hash}.thmb"
    magick "${magick_args[@]}" "${x_wall}"[0] -strip -resize 1000 -gravity center -extent 1000 -quality 90 "${tmp_thmb}" \
      && mv -f "${tmp_thmb}" "${thmbDir}/${x_hash}.thmb" || rm -f "${tmp_thmb}"
  fi
  [ ! -e "${thmbDir}/${x_hash}.sqre" ] && magick "${magick_args[@]}" "${x_wall}"[0] -strip -thumbnail 500x500^ -gravity center -extent 500x500 "${thmbDir}/${x_hash}.sqre.png" && mv "${thmbDir}/${x_hash}.sqre.png" "${thmbDir}/${x_hash}.sqre"
  if [ ! -e "${thmbDir}/${x_hash}.blur" ]; then
    tmp_blur="${thmbDir}/.${x_hash}.blur"
    magick "${magick_args[@]}" "${x_wall}"[0] -strip -scale 10% -blur 0x3 -resize 100% "${tmp_blur}" \
      && mv -f "${tmp_blur}" "${thmbDir}/${x_hash}.blur" || rm -f "${tmp_blur}"
  fi
  [ ! -e "${thmbDir}/${x_hash}.quad" ] && magick "${magick_args[@]}" "${thmbDir}/${x_hash}.sqre" \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "rectangle 400,0 500,500" -fill black -draw "rectangle 450,0 500,500" \) -alpha Off -compose CopyOpacity -composite "${thmbDir}/${x_hash}.quad.png" && mv "${thmbDir}/${x_hash}.quad.png" "${thmbDir}/${x_hash}.quad"

  if [ "${is_video}" -eq 1 ]; then
    rm -f "${temp_image}"
  fi
}

# shellcheck disable=SC2317
fn_wallcache_force() {
  local x_hash="${1}"
  local x_wall="${2}"
  local tmp_thmb tmp_blur
  local -a magick_args=()

  [[ -n "${WALLPAPER_MAGICK_MEM_MB:-}" ]] && magick_args+=(-limit memory "${WALLPAPER_MAGICK_MEM_MB}MiB")
  [[ -n "${WALLPAPER_MAGICK_MAP_MB:-}" ]] && magick_args+=(-limit map "${WALLPAPER_MAGICK_MAP_MB}MiB")
  [[ -n "${WALLPAPER_MAGICK_THREADS:-}" ]] && magick_args+=(-limit thread "${WALLPAPER_MAGICK_THREADS}")

  is_video=$(file --mime-type -b "${x_wall}" | grep -c '^video/')

  if [ "${is_video}" -eq 1 ]; then
    local temp_image="/tmp/${x_hash}.png"
    extract_thumbnail "${x_wall}" "${temp_image}"
    x_wall="${temp_image}"
  fi

  tmp_thmb="${thmbDir}/.${x_hash}.thmb"
  magick "${magick_args[@]}" "${x_wall}"[0] -strip -resize 1000 -gravity center -extent 1000 -quality 90 "${tmp_thmb}" \
    && mv -f "${tmp_thmb}" "${thmbDir}/${x_hash}.thmb" || rm -f "${tmp_thmb}"
  magick "${magick_args[@]}" "${x_wall}"[0] -strip -thumbnail 500x500^ -gravity center -extent 500x500 "${thmbDir}/${x_hash}.sqre.png" && mv "${thmbDir}/${x_hash}.sqre.png" "${thmbDir}/${x_hash}.sqre"
  tmp_blur="${thmbDir}/.${x_hash}.blur"
  magick "${magick_args[@]}" "${x_wall}"[0] -strip -scale 10% -blur 0x3 -resize 100% "${tmp_blur}" \
    && mv -f "${tmp_blur}" "${thmbDir}/${x_hash}.blur" || rm -f "${tmp_blur}"
  magick "${magick_args[@]}" "${thmbDir}/${x_hash}.sqre" \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "polygon 400,500 500,500 500,0 450,0" -fill black -draw "polygon 500,500 500,0 450,500" \) -alpha Off -compose CopyOpacity -composite "${thmbDir}/${x_hash}.quad.png" && mv "${thmbDir}/${x_hash}.quad.png" "${thmbDir}/${x_hash}.quad"

  if [ "${is_video}" -eq 1 ]; then
    rm -f "${temp_image}"
  fi

}

# Function to cache any links that are config related
fn_envar_cache() {
  if command -v rofi &>/dev/null; then
    if [[ ! "${XDG_DATA_DIRS:-}" =~ share/hypr ]]; then
      local xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
      local src_dir="${xdg_data_home}/hypr/rofi/themes"
      local dst_dir="${xdg_data_home}/rofi/themes"

      if [[ -d "${src_dir}" ]]; then
        mkdir -p "${dst_dir}"
        shopt -s nullglob
        local -a theme_files=("${src_dir}"/*)
        shopt -u nullglob
        if ((${#theme_files[@]} > 0)); then
          ln -snf "${theme_files[@]}" "${dst_dir}/"
        fi
      fi
    fi
  fi
}

export -f fn_wallcache fn_wallcache_force extract_thumbnail

#// evaluate options

wall_inputs=()
invalid_inputs=0

while getopts "w:t:f" option; do
  case $option in
    w) # generate cache for input wallpaper
      if [[ -z "${OPTARG}" ]] || [[ ! -f "${OPTARG}" ]]; then
        echo "Error: Input wallpaper \"${OPTARG}\" not found!" >&2
        invalid_inputs=1
        continue
      fi
      wall_inputs+=("$(realpath "${OPTARG}")")
      ;;
    t) # generate cache for input theme
      cacheIn="$(dirname "${HYPR_THEME_DIR}")/${OPTARG}"
      if [ ! -d "${cacheIn}" ]; then
        echo "Error: Input theme \"${OPTARG}\" not found!"
        exit 1
      fi
      ;;
    f) # full cache rebuild
      cacheIn="$(dirname "${HYPR_THEME_DIR}")"
      mode="_force"
      ;;
    *) # invalid option
      echo "... invalid option ..."
      echo "$(basename "${0}") -[option]"
      echo "w : generate cache for input wallpaper"
      echo "t : generate cache for input theme"
      echo "f : full cache rebuild"
      exit 1
      ;;
  esac
done

if [[ ${#wall_inputs[@]} -eq 0 ]] && [[ "${invalid_inputs}" -eq 1 ]]; then
  exit 1
fi

#// generate cache

fn_envar_cache

resolve_cache_limits
if [[ "${LOG_LEVEL:-}" == "debug" ]]; then
  print_log -sec "wallpaper" -stat "cache" "jobs=${WALLPAPER_CACHE_JOBS} mem=${WALLPAPER_MAGICK_MEM_MB}MiB map=${WALLPAPER_MAGICK_MAP_MB}MiB threads=${WALLPAPER_MAGICK_THREADS}"
fi

if [[ ${#wall_inputs[@]} -gt 0 ]]; then
  unset wallHash wallList
  for wall_input in "${wall_inputs[@]}"; do
    wallHash+=("$("${hashMech:-sha1sum}" "${wall_input}" | awk '{print $1}')")
    wallList+=("${wall_input}")
  done
else
  wallPathArray=("${cacheIn}")
  wallPathArray+=("${WALLPAPER_CUSTOM_PATHS[@]}")
  get_hashmap "${wallPathArray[@]}" --no-notify
fi

# shellcheck disable=SC2154
[[ ${#wallList[@]} -eq 0 ]] && exit 0
# shellcheck disable=SC2154
parallel --bar --link --jobs "${WALLPAPER_CACHE_JOBS}" "fn_wallcache${mode}" ::: "${wallHash[@]}" ::: "${wallList[@]}"
exit 0
