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

#// define functions

# shellcheck disable=SC2317
fn_wallcache() {
  local x_hash="${1}"
  local x_wall="${2}"
  local is_video
  local tmp_thmb tmp_blur
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
    magick "${x_wall}"[0] -strip -resize 1000 -gravity center -extent 1000 -quality 90 "${tmp_thmb}" \
      && mv -f "${tmp_thmb}" "${thmbDir}/${x_hash}.thmb" || rm -f "${tmp_thmb}"
  fi
  [ ! -e "${thmbDir}/${x_hash}.sqre" ] && magick "${x_wall}"[0] -strip -thumbnail 500x500^ -gravity center -extent 500x500 "${thmbDir}/${x_hash}.sqre.png" && mv "${thmbDir}/${x_hash}.sqre.png" "${thmbDir}/${x_hash}.sqre"
  if [ ! -e "${thmbDir}/${x_hash}.blur" ]; then
    tmp_blur="${thmbDir}/.${x_hash}.blur"
    magick "${x_wall}"[0] -strip -scale 10% -blur 0x3 -resize 100% "${tmp_blur}" \
      && mv -f "${tmp_blur}" "${thmbDir}/${x_hash}.blur" || rm -f "${tmp_blur}"
  fi
  [ ! -e "${thmbDir}/${x_hash}.quad" ] && magick "${thmbDir}/${x_hash}.sqre" \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "rectangle 400,0 500,500" -fill black -draw "rectangle 450,0 500,500" \) -alpha Off -compose CopyOpacity -composite "${thmbDir}/${x_hash}.quad.png" && mv "${thmbDir}/${x_hash}.quad.png" "${thmbDir}/${x_hash}.quad"

  if [ "${is_video}" -eq 1 ]; then
    rm -f "${temp_image}"
  fi
}

# shellcheck disable=SC2317
fn_wallcache_force() {
  local x_hash="${1}"
  local x_wall="${2}"
  local tmp_thmb tmp_blur

  is_video=$(file --mime-type -b "${x_wall}" | grep -c '^video/')

  if [ "${is_video}" -eq 1 ]; then
    local temp_image="/tmp/${x_hash}.png"
    extract_thumbnail "${x_wall}" "${temp_image}"
    x_wall="${temp_image}"
  fi

  tmp_thmb="${thmbDir}/.${x_hash}.thmb"
  magick "${x_wall}"[0] -strip -resize 1000 -gravity center -extent 1000 -quality 90 "${tmp_thmb}" \
    && mv -f "${tmp_thmb}" "${thmbDir}/${x_hash}.thmb" || rm -f "${tmp_thmb}"
  magick "${x_wall}"[0] -strip -thumbnail 500x500^ -gravity center -extent 500x500 "${thmbDir}/${x_hash}.sqre.png" && mv "${thmbDir}/${x_hash}.sqre.png" "${thmbDir}/${x_hash}.sqre"
  tmp_blur="${thmbDir}/.${x_hash}.blur"
  magick "${x_wall}"[0] -strip -scale 10% -blur 0x3 -resize 100% "${tmp_blur}" \
    && mv -f "${tmp_blur}" "${thmbDir}/${x_hash}.blur" || rm -f "${tmp_blur}"
  magick "${thmbDir}/${x_hash}.sqre" \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "polygon 400,500 500,500 500,0 450,0" -fill black -draw "polygon 500,500 500,0 450,500" \) -alpha Off -compose CopyOpacity -composite "${thmbDir}/${x_hash}.quad.png" && mv "${thmbDir}/${x_hash}.quad.png" "${thmbDir}/${x_hash}.quad"

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

single_wallpaper=0

while getopts "w:t:f" option; do
  case $option in
    w) # generate cache for input wallpaper
      if [ -z "${OPTARG}" ] || [ ! -f "${OPTARG}" ]; then
        echo "Error: Input wallpaper \"${OPTARG}\" not found!"
        exit 1
      fi
      cacheIn="$(realpath "${OPTARG}")"
      single_wallpaper=1
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

#// generate cache

fn_envar_cache

if [[ "${single_wallpaper}" -eq 1 ]]; then
  wallHash=("$(${hashMech:-sha1sum} "${cacheIn}" | awk '{print $1}')")
  wallList=("${cacheIn}")
else
  wallPathArray=("${cacheIn}")
  wallPathArray+=("${WALLPAPER_CUSTOM_PATHS[@]}")
  get_hashmap "${wallPathArray[@]}" --no-notify
fi

# shellcheck disable=SC2154
parallel --bar --link "fn_wallcache${mode}" ::: "${wallHash[@]}" ::: "${wallList[@]}"
exit 0
