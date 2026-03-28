#!/usr/bin/env bash
# shellcheck disable=SC1091,SC1090

find_wallpapers() {
  local wallSource="$1"
  shift
  local -a supported_files=("$@")

  if [ -z "${wallSource}" ]; then
    print_log -err "ERROR: wallSource is empty"
    return 1
  fi

  # Build find arguments safely using arrays (no eval needed)
  local -a find_args=(-H "${wallSource}" -type f \()
  local first_ext=true
  local ext

  for ext in "${supported_files[@]}"; do
    if [[ "${first_ext}" == true ]]; then
      find_args+=(-iname "*.${ext}")
      first_ext=false
    else
      find_args+=(-o -iname "*.${ext}")
    fi
  done
  find_args+=(\) ! -path "*/logo/*" -exec "${HYPR_HASH_COMMAND}" {} +)

  [ "${LOG_LEVEL}" == "debug" ] && print_log -g "DEBUG:" -b "Running find with args:" "${find_args[*]}"

  local tmpfile error_output
  tmpfile=$(mktemp)
  find "${find_args[@]}" 2>"$tmpfile" | sort -k2
  error_output=$(<"$tmpfile") && rm -f "$tmpfile"
  [ -n "${error_output}" ] && print_log -err "ERROR:" -b "found an error: " -r "${error_output}" -y " skipping..."
}

get_hashmap() {
  local no_notify=0
  local skipStrays=0
  local -a wall_sources=()
  local wallSource=""
  local hashMap=""
  local hash=""
  local image=""

  wallHash=()
  wallList=()
  no_wallpapers=()

  # Initialize supported file extensions (safe: no eval needed)
  local -a supported_files=(
    "gif"
    "jpg"
    "jpeg"
    "png"
    "${WALLPAPER_FILETYPES[@]}"
  )
  if (( ${#WALLPAPER_OVERRIDE_FILETYPES[@]} > 0 )); then
    supported_files=("${WALLPAPER_OVERRIDE_FILETYPES[@]}")
  fi

  while (($# > 0)); do
    case "$1" in
      --no-notify)
        no_notify=1
        shift
        ;;
      --skipstrays)
        skipStrays=1
        shift
        ;;
      --)
        shift
        wall_sources=("$@")
        break
        ;;
      -*)
        print_log -err "ERROR:" -b "unknown get_hashmap option:" "$1"
        return 1
        ;;
      *)
        wall_sources=("$@")
        break
        ;;
    esac
  done

  for wallSource in "${wall_sources[@]}"; do

    [ "${LOG_LEVEL}" == "debug" ] && print_log -g "DEBUG:" -b "wallpaper source path:" "${wallSource}"

    [ -z "${wallSource}" ] && continue
    wallSource="$(realpath "${wallSource}")"

    [ -e "${wallSource}" ] || {
      print_log -err "ERROR:" -b "wallpaper source does not exist:" "${wallSource}" -y " skipping..."
      continue
    }

    [ "${LOG_LEVEL}" == "debug" ] && print_log -g "DEBUG:" -b "wallSource path:" "${wallSource}"

    hashMap=$(find_wallpapers "${wallSource}" "${supported_files[@]}")

    if [ -z "${hashMap}" ]; then
      no_wallpapers+=("${wallSource}")
      print_log -warn "No compatible wallpapers found in: " "${wallSource}"
      continue
    fi

    while read -r hash image; do
      wallHash+=("${hash}")
      wallList+=("${image}")
    done <<<"${hashMap}"
  done

  # Notify the list of directories without compatible wallpapers
  if [ "${#no_wallpapers[@]}" -gt 0 ]; then
    print_log -warn "No compatible wallpapers found in:" "${no_wallpapers[*]}"
  fi

  if [[ "${#wallList[@]}" -eq 0 ]]; then
    if [[ "${skipStrays}" -eq 1 ]]; then
      return 1
    else
      echo "ERROR: No image found in any source"
      [ -n "${no_notify}" ] && dunstify -a "Global control" -t 5000 -i "dialog-warning" "WARNING: No compatible wallpapers found in: ${no_wallpapers[*]}"
      exit 1
    fi
  fi

}

# Populate sorted theme metadata from `$HYPR_CONFIG_HOME/themes` and repair
# broken `wall.set` links when a theme still has valid wallpapers.
# shellcheck disable=SC2120
get_themes() {
  thmSortS=()
  thmListS=()
  thmWallS=()
  thmSort=()
  thmList=()
  thmWall=()

  while read -r thmDir; do
    local realWallPath
    realWallPath="$(readlink "${thmDir}/wall.set")"
    if [ ! -e "${realWallPath}" ]; then
      get_hashmap --skipstrays "${thmDir}" || continue
      echo "fixing link :: ${thmDir}/wall.set"
      ln -fs "${wallList[0]}" "${thmDir}/wall.set"
    fi
    [ -f "${thmDir}/.sort" ] && thmSortS+=("$(head -1 "${thmDir}/.sort")") || thmSortS+=("0")
    thmWallS+=("${realWallPath}")
    thmListS+=("${thmDir##*/}") # Use this instead of basename
  done < <(find -H "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d)

  while IFS='|' read -r sort theme wall; do
    thmSort+=("${sort}")
    thmList+=("${theme}")
    thmWall+=("${wall}")
  done < <(paste -d '|' <(printf "%s\n" "${thmSortS[@]}") <(printf "%s\n" "${thmListS[@]}") <(printf "%s\n" "${thmWallS[@]}") | sort -n -k 1 -k 2)
}

# Print the configured hash for a readable image file.
set_hash() {
  local hashImage="${1}"

  # Validate input
  if [[ -z "${hashImage}" ]]; then
    return 1
  fi
  if [[ ! -r "${hashImage}" ]]; then
    return 1
  fi

  "${HYPR_HASH_COMMAND}" "${hashImage}" | awk '{print $1}'
}

# Extract a thumbnail image for a video file with ffmpeg.
# shellcheck disable=SC2317
extract_thumbnail() {
  local x_wall="${1}"
  x_wall=$(realpath "${x_wall}")
  local temp_image="${2}"
  ffmpeg -y -i "${x_wall}" -vf "thumbnail,scale=1000:-1" -frames:v 1 -update 1 "${temp_image}" &>/dev/null
}

# Function to check if the file is supported by the wallpaper backend
accepted_mime_types() {
  local file actual_mime mime_type
  local -a mime_types_array=()

  if (( $# < 2 )); then
    return 1
  fi

  file="${*: -1}"
  if [[ "$(declare -p "$1" 2>/dev/null || true)" == declare\ -a* ]]; then
    local -n mime_types_ref="$1"
    mime_types_array=("${mime_types_ref[@]}")
  else
    mime_types_array=("${@:1:$#-1}")
  fi

  actual_mime="$(file --mime-type -b "${file}" 2>/dev/null || true)"
  for mime_type in "${mime_types_array[@]}"; do
    [[ "${actual_mime}" == "${mime_type}"* ]] && return 0
  done

  print_log -err "File type not supported for this wallpaper backend."
  dunstify -u critical -a "Global control" -i "dialog-error" "File type not supported for this wallpaper backend."
  return 1
}
