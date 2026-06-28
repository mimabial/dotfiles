#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Shared hyprlock MPRIS/media helpers.

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

os_pretty_name() {
  awk -F'=' '/^PRETTY_NAME=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release
}

mpris_thumb() {
  local player=${1:-""}
  local thumb="${HYPR_CACHE_HOME}/landing/mpris"
  local art_url=""
  local video_url=""
  local video_id=""
  local size=""
  local monitor_info=""
  local width=""
  local height=""

  art_url=$(playerctl -p "${player}" metadata --format '{{mpris:artUrl}}' 2>/dev/null)
  if [[ -z "${art_url}" ]]; then
    video_url=$(playerctl -p "${player}" metadata --format '{{xesam:url}}' 2>/dev/null)
    if [[ "${video_url}" =~ youtube\.com/watch\?v=([^&]+) ]] || [[ "${video_url}" =~ youtu\.be/([^?]+) ]]; then
      video_id="${BASH_REMATCH[1]}"
      art_url="https://img.youtube.com/vi/${video_id}/maxresdefault.jpg"
      echo "YouTube thumbnail extracted: ${art_url}" >"${thumb}.log"
    fi
  fi

  [[ "${art_url}" == "$(cat "${thumb}.lnk" 2>/dev/null)" && -f "${thumb}.png" ]] && return 0

  echo "${art_url}" >"${thumb}.lnk"
  if curl -Lso "${thumb}.art" "${art_url}" 2>/dev/null; then
    size=$(identify -format "%w" "${thumb}.art" 2>/dev/null)
    if [[ "${size:-0}" -lt 200 && "${art_url}" =~ youtube ]]; then
      art_url="${art_url/maxresdefault/hqdefault}"
      curl -Lso "${thumb}.art" "${art_url}" 2>/dev/null
    fi

    magick "${MAGICK_LIMITS[@]}" "${thumb}.art" -quality 50 "${thumb}.png" 2>/dev/null || return 1

    monitor_info=$(hyprctl monitors -j | jq -r '.[0] | "\(.width)x\(.height)"')
    IFS=x read -r width height <<<"${monitor_info}"
    magick "${MAGICK_LIMITS[@]}" "${thumb}.art" -blur 20x3 -resize "${width}x^" -gravity center -extent "${width}x${height}!" "${thumb}.blurred.png" 2>/dev/null

    reload_hyprlock
  fi
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

fn_artist() {
  local player=${1:-$(mpris_default_player)}

  if ! mpris_active_player_value "${player}" "{{xesam:artist}}"; then
    os_pretty_name
  fi
}

fn_source() {
  local player=${1:-$(mpris_default_player)}
  local player_status=""

  player_status="$(mpris_player_status "${player}")"
  if mpris_player_active "${player_status}"; then
    mpris_icon "${player}"
  fi
}

fn_status() {
  local player=${1:-$(mpris_default_player)}
  local player_status=""

  player_status="$(mpris_player_status "${player}")"
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

  player_status="$(mpris_player_status "${player}")"
  if mpris_player_active "${player_status}"; then
    mpris_thumb "${player}"
    return 0
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
