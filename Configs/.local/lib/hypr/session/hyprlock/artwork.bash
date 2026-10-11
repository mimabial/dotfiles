hyprlock_queue_artwork_update() {
  local -n queued_paths_ref="$1"
  local lock="${queued_paths_ref[artwork_lock]}" lock_fd fd path
  [[ -d "${lock%/*}" ]] || mkdir -m 700 "${lock%/*}" || return 1
  exec {lock_fd}>"${lock}"
  if ! flock -n "${lock_fd}" || hyprlock_artwork_is_cached "$1" "$2"; then
    exec {lock_fd}>&-
    return 0
  fi
  # hyprlock reads a label's pipe until every holder closes it, background work included
  ( for path in /proc/self/fd/*; do
      fd="${path##*/}"
      ((fd < 3 || fd == lock_fd)) || exec {fd}>&-
    done
    source "${BASH_SOURCE[0]%/*}/../../core/math.bash"
    source "${BASH_SOURCE[0]%/*}/../../core/processes.bash"
    source "${BASH_SOURCE[0]%/*}/process.bash"
    source "${BASH_SOURCE[0]%/*}/images.bash"
    hyprlock_init_magick
    hyprlock_render_artwork "$1" "$2"
  ) >/dev/null 2>&1 &
  exec {lock_fd}>&-
}

MPRIS_ART_MIN_WIDTH_PX=200
MPRIS_ART_RENDER_VERSION="v2:"

hyprlock_artwork_is_cached() {
  local -n cached_paths_ref="$1"
  local artwork_base="${cached_paths_ref[artwork_base]}" cache_key=fallback cached_key="" art_url=""
  if mpris_status_is_active "$(mpris_player_status "$2" || true)"; then
    art_url="$(mpris_artwork_url "$2")"
    [[ -z "${art_url}" ]] || cache_key="${MPRIS_ART_RENDER_VERSION}${art_url}"
  fi
  IFS= read -r cached_key 2>/dev/null <"${artwork_base}.lnk" || true
  [[ "${cache_key}" == "${cached_key}" && -s "${artwork_base}.png" ]] || return 1
  [[ "${cache_key}" != fallback ]] || {
    [[ -s "${artwork_base}.blurred.png" && ! "${cached_paths_ref[palette]}" -nt "${artwork_base}.lnk" && ! "${cached_paths_ref[icon]}" -nt "${artwork_base}.lnk" ]]
  }
}

# YouTube serves a tiny placeholder when a video has no maxres thumbnail.
mpris_download_art() {
  local url="$1" output_path="$2" width=""

  curl --fail --location --silent --show-error --output "${output_path}" -- "${url}" 2>/dev/null || return 1
  width="$(identify -format "%w" "${output_path}" 2>/dev/null || true)"
  if [[ "${width}" =~ ^[0-9]+$ ]] && ((width < MPRIS_ART_MIN_WIDTH_PX)) && [[ "${url}" == *youtube* ]]; then
    curl --fail --location --silent --show-error --output "${output_path}" -- "${url/maxresdefault/hqdefault}" 2>/dev/null
  fi
}

mpris_render_art() {
  local art="$1" square="$2" blurred="$3" width="" height=""

  # Layouts frame the art in a square; thumbnails arrive letterboxed, so drop the
  # bars and centre-crop to fill it.
  magick "${HYPRLOCK_MAGICK_ARGS[@]}" "${art}" -fuzz 8% -trim +repage \
    -gravity center -extent '%[fx:min(w,h)]x%[fx:min(w,h)]' \
    -quality 50 "png:${square}" 2>/dev/null || return 1

  IFS=x read -r width height <<<"$(hyprctl monitors -j 2>/dev/null | jq -r '.[0] | "\(.width)x\(.height)"' 2>/dev/null || true)"
  [[ "${width}" =~ ^[0-9]+$ && "${height}" =~ ^[0-9]+$ ]] || return 0
  magick "${HYPRLOCK_MAGICK_ARGS[@]}" "${art}" -blur 20x3 -resize "${width}x^" -gravity center -extent "${width}x${height}!" "png:${blurred}" 2>/dev/null
}

# The song may change while its cover is downloading. Never publish a
# completed image unless it still belongs to the selected player and track.
mpris_art_still_current() {
  [[ "$(mpris_selected_player)" == "$1" && "$(mpris_artwork_url "$1")" == "$2" ]]
}

hyprlock_refresh_media_artwork() {
  local -n art_paths_ref="$1"
  local player=${2:-""}
  local artwork_base="${art_paths_ref[artwork_base]}"
  local art_url="" cache_key="" cached_key="" staging_dir=""

  art_url="$(mpris_artwork_url "${player}")"
  [[ -n "${art_url}" ]] || return 1
  cache_key="${MPRIS_ART_RENDER_VERSION}${art_url}"
  IFS= read -r cached_key 2>/dev/null <"${artwork_base}.lnk" || true
  [[ "${cache_key}" == "${cached_key}" && -s "${artwork_base}.png" ]] && return 0

  mkdir -p "${artwork_base%/*}"
  staging_dir="$(mktemp -d "${artwork_base}.XXXXXX")" || return 1
  if ! mpris_download_art "${art_url}" "${staging_dir}/art" ||
    ! mpris_render_art "${staging_dir}/art" "${staging_dir}/png" "${staging_dir}/blurred.png" ||
    ! mpris_art_still_current "${player}" "${art_url}"; then
    rm -rf -- "${staging_dir}"
    return 1
  fi

  printf '%s\n' "${cache_key}" >"${staging_dir}/lnk"
  mv -f -- "${staging_dir}/art" "${artwork_base}.art"
  mv -f -- "${staging_dir}/png" "${artwork_base}.png"
  [[ ! -e "${staging_dir}/blurred.png" ]] || mv -f -- "${staging_dir}/blurred.png" "${artwork_base}.blurred.png"
  mv -f -- "${staging_dir}/lnk" "${artwork_base}.lnk"
  rm -rf -- "${staging_dir}"
  hyprlock_reload_process
}

hyprlock_artwork_path() {
  local -n art_paths_ref="$1"
  echo "${art_paths_ref[artwork_base]}.art"
}

hyprlock_update_artwork() (
  local -n updated_paths_ref="$1"
  local lock="${updated_paths_ref[artwork_lock]}" lock_fd
  [[ -d "${lock%/*}" ]] || mkdir -m 700 "${lock%/*}" || return 1
  exec {lock_fd}>"${lock}"
  flock -n "${lock_fd}" || return 0
  local player="${2:-$(mpris_selected_player)}"
  hyprlock_artwork_is_cached "$1" "${player}" && return 0
  hyprlock_render_artwork "$1" "${player}"
)

hyprlock_render_artwork() {
  local -n art_paths_ref="$1"
  local player="$2"
  local artwork_base="${art_paths_ref[artwork_base]}"
  local player_status=""
  local temp_colored="${art_paths_ref[landing]}/hypr-colored.tmp.png"
  player_status="$(mpris_player_status "${player}" || true)"
  if mpris_status_is_active "${player_status}"; then
    if hyprlock_refresh_media_artwork "$1" "${player}"; then
      return 0
    fi
  fi

  rm -f "${artwork_base}.lnk" "${artwork_base}.art" 2>/dev/null
  mkdir -p "${artwork_base%/*}"
  hyprlock_render_fallback_icon "$1" "${temp_colored}" || return 1
  if [[ -f "${temp_colored}" ]]; then
    if ! cmp -s "${temp_colored}" "${artwork_base}.png"; then
      mv "${temp_colored}" "${artwork_base}.png"
      hyprlock_reload_process
    else
      rm -f "${temp_colored}"
    fi
  fi
  hyprlock_clear_blurred_art "$1" "${artwork_base}.blurred.png" || return 1
  printf '%s\n' fallback >"${artwork_base}.lnk"
}
