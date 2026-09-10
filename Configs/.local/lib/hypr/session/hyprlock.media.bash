#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
mpris_icon() {
  local player=${1:-default}
  declare -A player_dict=(
    ["default"]=""
    ["spotify"]=""
    ["firefox"]=""
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
  echo ""
}

mpris_default_player() {
  local first=""
  IFS= read -r first < <(playerctl --list-all 2>/dev/null)
  printf '%s' "${first}"
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

mpris_cleanup_temps() {
  local path=""
  for path in "$@"; do
    [[ -n "${path}" ]] && rm -f -- "${path}"
  done
}

os_pretty_name() {
  awk -F'=' '/^PRETTY_NAME=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release
}

mpris_thumb() {
  local player=${1:-""}
  local thumb="${HYPR_CACHE_HOME}/landing/mpris"
  local art_url=""
  local fetch_url=""
  local cache_key=""
  local size=""
  local monitor_info=""
  local width=""
  local height=""
  local art_tmp=""
  local png_tmp=""
  local blurred_tmp=""
  local link_tmp=""

  art_url="$(mpris_art_url "${player}")"
  [[ -n "${art_url}" ]] || return 1
  fetch_url="${art_url}"
  cache_key="v2:${art_url}"

  [[ "${cache_key}" == "$(cat "${thumb}.lnk" 2>/dev/null)" && -s "${thumb}.png" ]] && return 0

  mkdir -p "$(dirname "${thumb}")"
  art_tmp="$(mktemp "${thumb}.art.XXXXXX")" || return 1
  png_tmp="$(mktemp "${thumb}.png.XXXXXX")" || {
    mpris_cleanup_temps "${art_tmp}"
    return 1
  }
  blurred_tmp="$(mktemp "${thumb}.blurred.png.XXXXXX")" || {
    mpris_cleanup_temps "${art_tmp}" "${png_tmp}"
    return 1
  }
  link_tmp="$(mktemp "${thumb}.lnk.XXXXXX")" || {
    mpris_cleanup_temps "${art_tmp}" "${png_tmp}" "${blurred_tmp}"
    return 1
  }

  if ! curl --fail --location --silent --show-error --output "${art_tmp}" -- "${fetch_url}" 2>/dev/null; then
    mpris_cleanup_temps "${art_tmp}" "${png_tmp}" "${blurred_tmp}" "${link_tmp}"
    return 1
  fi

  size="$(identify -format "%w" "${art_tmp}" 2>/dev/null || true)"
  if [[ "${size}" =~ ^[0-9]+$ ]] && ((size < 200)) && [[ "${fetch_url}" == *youtube* ]]; then
    fetch_url="${fetch_url/maxresdefault/hqdefault}"
    if ! curl --fail --location --silent --show-error --output "${art_tmp}" -- "${fetch_url}" 2>/dev/null; then
      mpris_cleanup_temps "${art_tmp}" "${png_tmp}" "${blurred_tmp}" "${link_tmp}"
      return 1
    fi
  fi

  if ! magick "${MAGICK_LIMITS[@]}" "${art_tmp}" -quality 50 "png:${png_tmp}" 2>/dev/null; then
    mpris_cleanup_temps "${art_tmp}" "${png_tmp}" "${blurred_tmp}" "${link_tmp}"
    return 1
  fi

  monitor_info="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0] | "\(.width)x\(.height)"' 2>/dev/null || true)"
  IFS=x read -r width height <<<"${monitor_info}"
  if [[ "${width}" =~ ^[0-9]+$ && "${height}" =~ ^[0-9]+$ ]]; then
    if ! magick "${MAGICK_LIMITS[@]}" "${art_tmp}" -blur 20x3 -resize "${width}x^" -gravity center -extent "${width}x${height}!" "png:${blurred_tmp}" 2>/dev/null; then
      mpris_cleanup_temps "${art_tmp}" "${png_tmp}" "${blurred_tmp}" "${link_tmp}"
      return 1
    fi
  else
    rm -f -- "${blurred_tmp}"
    blurred_tmp=""
  fi

  # The song may change while its cover is downloading. Never publish a
  # completed image unless it still belongs to the selected player and track.
  if [[ "$(mpris_default_player)" != "${player}" || "$(mpris_art_url "${player}")" != "${art_url}" ]]; then
    mpris_cleanup_temps "${art_tmp}" "${png_tmp}" "${blurred_tmp}" "${link_tmp}"
    return 1
  fi

  printf '%s\n' "${cache_key}" >"${link_tmp}"
  mv -f -- "${art_tmp}" "${thumb}.art"
  mv -f -- "${png_tmp}" "${thumb}.png"
  [[ -z "${blurred_tmp}" ]] || mv -f -- "${blurred_tmp}" "${thumb}.blurred.png"
  mv -f -- "${link_tmp}" "${thumb}.lnk"
  reload_hyprlock
  return 0
}

convert_length() {
  local length=$1
  local seconds=$((length / 1000000))
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))
  printf "%d:%02d\n" "${minutes}" "${remaining_seconds}"
}

truncate_with_ellipsis() {
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
    truncate_with_ellipsis "${title}"
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

fn_length() {
  local player=${1:-$(mpris_default_player)}
  local length=""

  length="$(mpris_active_player_value "${player}" "{{mpris:length}}" || true)"
  if [[ -n "${length}" ]]; then
    convert_length "${length}"
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
    if mpris_thumb "${player}"; then
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
