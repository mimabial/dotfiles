#!/usr/bin/env bash
SEEK_SECONDS=10
mpris_icon() {
  local player=${1:-default}
  declare -A player_dict=(
    ["default"]=""
    ["spotify"]=""
    ["firefox"]=""
    ["fftab"]=""  # the browser bridge names a player per tab
    ["vlc"]="嗢"
    ["google-chrome"]=""
    ["opera"]=""
    ["brave"]=""
  )
  local key=""

  for key in "${!player_dict[@]}"; do
    if [[ ${player} == "$key"* ]]; then
      echo "${player_dict[$key]}"
      return
    fi
  done
  echo "${player_dict[default]}"
}

# playerctl lists alphabetically, so only the status can pick the player that sounds.
mpris_default_player() {
  local -a names=() statuses=()
  mapfile -t names < <(playerctl --list-all 2>/dev/null)
  mapfile -t statuses < <(playerctl -a status 2>/dev/null)
  local index="" paused=""
  for index in "${!names[@]}"; do
    case "${statuses[index]:-}" in
      Playing)
        printf '%s' "${names[index]}"
        return
        ;;
      Paused) [[ -n ${paused} ]] || paused="${names[index]}" ;;
    esac
  done
  printf '%s' "${paused:-${names[0]:-}}"
}

mpris_player_status() {
  playerctl -p "${1}" status 2>/dev/null
}

mpris_player_active() {
  case "${1:-}" in
    Playing | Paused) return 0 ;;
    *) return 1 ;;
  esac
}

mpris_active_player_value() {
  local player="$1"
  local format="$2"
  local out=""
  out="$(playerctl -p "${player}" metadata --format $'{{status}}\t'"${format}" 2>/dev/null)" || return 1
  local status="${out%%$'\t'*}"
  local value="${out#*$'\t'}"
  mpris_player_active "${status}" || return 1
  printf '%s\n' "${value}"
}

mpris_art_url() {
  local player="$1"
  local art_url=""
  local video_url=""
  local video_id=""
  local youtube_watch_re='youtube\.com/watch\?v=([^&]+)'
  local youtube_short_re='youtu\.be/([^?]+)'

  art_url="$(playerctl -p "${player}" metadata --format '{{mpris:artUrl}}' 2>/dev/null)"
  if [[ -z "${art_url}" ]]; then
    video_url="$(playerctl -p "${player}" metadata --format '{{xesam:url}}' 2>/dev/null)"
    if [[ "${video_url}" =~ ${youtube_watch_re} ]] || [[ "${video_url}" =~ ${youtube_short_re} ]]; then
      video_id="${BASH_REMATCH[1]}"
      art_url="https://img.youtube.com/vi/${video_id}/maxresdefault.jpg"
    fi
  fi

  printf '%s\n' "${art_url}"
}

os_pretty_name() {
  awk -F'=' '/^PRETTY_NAME=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release
}

MPRIS_ART_MIN_WIDTH_PX=200

# YouTube serves a tiny placeholder when a video has no maxres thumbnail.
mpris_download_art() {
  local url="$1" out="$2" width=""

  curl --fail --location --silent --show-error --output "${out}" -- "${url}" 2>/dev/null || return 1
  width="$(identify -format "%w" "${out}" 2>/dev/null || true)"
  if [[ "${width}" =~ ^[0-9]+$ ]] && ((width < MPRIS_ART_MIN_WIDTH_PX)) && [[ "${url}" == *youtube* ]]; then
    curl --fail --location --silent --show-error --output "${out}" -- "${url/maxresdefault/hqdefault}" 2>/dev/null
  fi
}

mpris_render_art() {
  local art="$1" square="$2" blurred="$3" width="" height=""

  # Layouts frame the art in a square; thumbnails arrive letterboxed, so drop the
  # bars and centre-crop to fill it.
  magick "${MAGICK_LIMITS[@]}" "${art}" -fuzz 8% -trim +repage \
    -gravity center -extent '%[fx:min(w,h)]x%[fx:min(w,h)]' \
    -quality 50 "png:${square}" 2>/dev/null || return 1

  IFS=x read -r width height <<<"$(hyprctl monitors -j 2>/dev/null | jq -r '.[0] | "\(.width)x\(.height)"' 2>/dev/null || true)"
  [[ "${width}" =~ ^[0-9]+$ && "${height}" =~ ^[0-9]+$ ]] || return 0
  magick "${MAGICK_LIMITS[@]}" "${art}" -blur 20x3 -resize "${width}x^" -gravity center -extent "${width}x${height}!" "png:${blurred}" 2>/dev/null
}

# The song may change while its cover is downloading. Never publish a
# completed image unless it still belongs to the selected player and track.
mpris_art_still_current() {
  [[ "$(mpris_default_player)" == "$1" && "$(mpris_art_url "$1")" == "$2" ]]
}

refresh_mpris_artwork() {
  local player=${1:-""}
  local thumb="${HYPR_CACHE_HOME}/landing/mpris"
  local art_url="" cache_key="" work=""

  art_url="$(mpris_art_url "${player}")"
  [[ -n "${art_url}" ]] || return 1
  cache_key="v2:${art_url}"
  [[ "${cache_key}" == "$(cat "${thumb}.lnk" 2>/dev/null)" && -s "${thumb}.png" ]] && return 0

  mkdir -p "$(dirname "${thumb}")"
  work="$(mktemp -d "${thumb}.XXXXXX")" || return 1
  if ! mpris_download_art "${art_url}" "${work}/art" ||
    ! mpris_render_art "${work}/art" "${work}/png" "${work}/blurred.png" ||
    ! mpris_art_still_current "${player}" "${art_url}"; then
    rm -rf -- "${work}"
    return 1
  fi

  printf '%s\n' "${cache_key}" >"${work}/lnk"
  mv -f -- "${work}/art" "${thumb}.art"
  mv -f -- "${work}/png" "${thumb}.png"
  [[ ! -e "${work}/blurred.png" ]] || mv -f -- "${work}/blurred.png" "${thumb}.blurred.png"
  mv -f -- "${work}/lnk" "${thumb}.lnk"
  rm -rf -- "${work}"
  reload_hyprlock
}

format_mpris_length() {
  local length=$1
  local microseconds_per_second=1000000
  local seconds=$((length / microseconds_per_second))
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))
  printf "%d:%02d\n" "${minutes}" "${remaining_seconds}"
}

truncate_mpris_title() {
  local value="$1"
  local max_length="${2:-40}"

  if ((${#value} > max_length)); then
    printf '%s...\n' "${value:0:max_length}"
  else
    printf '%s\n' "${value}"
  fi
}

fn_title() {
  local player=${1:-$(mpris_default_player)}
  local title=""

  title="$(mpris_active_player_value "${player}" "{{xesam:title}}" || true)"
  if [[ -n "${title}" ]]; then
    truncate_mpris_title "${title}"
  else
    echo "${USER^}"
  fi
}

fn_mpris() {
  local player=${1:-$(mpris_default_player)}
  mpris_player_active "$(mpris_player_status "${player}" || true)" || return 1
  fn_title "${player}"
}

fn_artist() {
  local player=${1:-$(mpris_default_player)}

  if ! mpris_active_player_value "${player}" "{{xesam:artist}}"; then
    os_pretty_name
  fi
}

fn_source() {
  local player=${1:-$(mpris_default_player)}
  local player_status=""

  player_status="$(mpris_player_status "${player}" || true)"
  if mpris_player_active "${player_status}"; then
    mpris_icon "${player}"
  fi
}

fn_status() {
  local player=${1:-$(mpris_default_player)}
  local player_status=""

  player_status="$(mpris_player_status "${player}" || true)"
  case "${player_status}" in
    Playing) echo "▶" ;;
    Paused) echo "⏸" ;;
    *) echo "" ;;
  esac
}

fn_control() {
  local player=""
  player="$(mpris_default_player)"
  [[ -n "${player}" ]] || return 0
  case "$1" in
    rewind) playerctl -p "${player}" position "${SEEK_SECONDS}-" ;;
    forward) playerctl -p "${player}" position "${SEEK_SECONDS}+" ;;
    *) playerctl -p "${player}" "$1" ;;
  esac
}

fn_length() {
  local player=${1:-$(mpris_default_player)}
  local length=""

  length="$(mpris_active_player_value "${player}" "{{mpris:length}}" || true)"
  if [[ -n "${length}" ]]; then
    format_mpris_length "${length}"
  fi
}

fn_art() {
  echo "${HYPR_CACHE_HOME}/landing/mpris.art"
}

fn_update_art() {
  local player=${1:-$(mpris_default_player)}
  local thumb="${HYPR_CACHE_HOME}/landing/mpris"
  local player_status=""
  local temp_colored="${HYPR_CACHE_HOME}/landing/hypr-colored.tmp.png"
  local lock_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
  local lock="${lock_dir}/hyprlock-art.lock"
  local lock_fd=""

  [[ -d "${lock_dir}" ]] || mkdir -m 700 "${lock_dir}" || return 1
  exec {lock_fd}>"${lock}"
  flock -n "${lock_fd}" || return 0

  player_status="$(mpris_player_status "${player}" || true)"
  if mpris_player_active "${player_status}"; then
    if refresh_mpris_artwork "${player}"; then
      return 0
    fi
  fi

  rm -f "${thumb}.lnk" "${thumb}.art" 2>/dev/null
  colorize_fallback_icon "${temp_colored}"
  if [[ -f "${temp_colored}" ]]; then
    if ! cmp -s "${temp_colored}" "${thumb}.png"; then
      mv "${temp_colored}" "${thumb}.png"
      reload_hyprlock
    else
      rm -f "${temp_colored}"
    fi
  fi
  set_mpris_blurred_empty "${thumb}.blurred.png"
}
