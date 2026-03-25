#!/usr/bin/env bash
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

  for key in "${!player_dict[@]}"; do
    if [[ ${player} == "$key"* ]]; then
      echo "${player_dict[$key]}"
      return
    fi
  done
  echo "" # Default icon if no match is found
}

mpris_thumb() {
  local player=${1:-""}
  THUMB="${HYPR_CACHE_HOME}/landing/mpris"

  artUrl=$(playerctl -p "${player}" metadata --format '{{mpris:artUrl}}' 2>/dev/null)
  if [ -z "$artUrl" ]; then
    videoUrl=$(playerctl -p "${player}" metadata --format '{{xesam:url}}' 2>/dev/null)
    if [[ "$videoUrl" =~ youtube\.com/watch\?v=([^&]+) ]] || [[ "$videoUrl" =~ youtu\.be/([^?]+) ]]; then
      videoId="${BASH_REMATCH[1]}"
      # Try maxresdefault first (1920x1080), fallback to hqdefault (480x360)
      artUrl="https://img.youtube.com/vi/${videoId}/maxresdefault.jpg"
      echo "YouTube thumbnail extracted: $artUrl" >"${THUMB}.log"
    fi
  fi
  # Check if already cached
  [ "${artUrl}" == "$(cat "${THUMB}".lnk 2>/dev/null)" ] && [ -f "${THUMB}".png ] && return 0
  # Save new URL
  echo "${artUrl}" >"${THUMB}".lnk
  # Download and process
  if curl -Lso "${THUMB}".art "$artUrl" 2>/dev/null; then
    # Check if it's valid (YouTube returns 120x90 placeholder for invalid maxresdefault)
    size=$(identify -format "%w" "${THUMB}".art 2>/dev/null)
    if [ "$size" -lt 200 ] 2>/dev/null && [[ "$artUrl" =~ youtube ]]; then
      # Try hqdefault instead for YouTube
      artUrl="${artUrl/maxresdefault/hqdefault}"
      curl -Lso "${THUMB}".art "$artUrl" 2>/dev/null
    fi
    # Create regular thumbnail
    magick "${MAGICK_LIMITS[@]}" "${THUMB}.art" -quality 50 "${THUMB}.png" 2>/dev/null || return 1
    # Create blurred version - use physical monitor resolution (hyprlock handles scaling with fractional_scaling=1)
    local monitor_info=$(hyprctl monitors -j | jq -r '.[0] | "\(.width)x\(.height)"')
    local width=$(echo "$monitor_info" | cut -d'x' -f1)
    local height=$(echo "$monitor_info" | cut -d'x' -f2)
    magick "${MAGICK_LIMITS[@]}" "${THUMB}.art" -blur 20x3 -resize ${width}x^ -gravity center -extent ${width}x${height}\! "${THUMB}.blurred.png" 2>/dev/null

    reload_hyprlock
  fi
}

# Function to convert microseconds to minutes and seconds
convert_length() {
  local length=$1
  local seconds=$((length / 1000000))
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))
  printf "%d:%02d\n" $minutes $remaining_seconds
}

fn_title() {
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  local player_status=""
  local title=""
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    title="$(playerctl -p "${player}" metadata --format "{{xesam:title}}" 2>/dev/null)"
    # Truncate to 40 characters (adjust as needed)
    echo "${title:0:40}$([ ${#title} -gt 40 ] && echo '...')"
  else
    echo "${USER^}"
  fi
}

fn_artist() {
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    playerctl -p "${player}" metadata --format "{{xesam:artist}}" 2>/dev/null
  else
    awk -F'=' '/^PRETTY_NAME=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release
  fi
}

fn_source() {
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    mpris_icon "${player}"
  fi
}

fn_status() {
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  case "${player_status}" in
    Playing)
      echo "▶" # or echo "Playing"
      ;;
    Paused)
      echo "⏸" # or echo "Paused"
      ;;
    *)
      echo "" # or echo "Stopped"
      ;;
  esac
}

fn_length() {
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    length=$(playerctl -p "${player}" metadata --format "{{mpris:length}}" 2>/dev/null)
    if [ -n "$length" ]; then
      convert_length "$length"
    fi
  fi
}

fn_mpris() {
  # Combined MPRIS formatter used by the lockscreen text widgets.
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  THUMB="${HYPR_CACHE_HOME}/landing/mpris"
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]]; then
    playerctl -p "${player}" metadata --format "{{xesam:title}} $(mpris_icon "${player}")  {{xesam:artist}}" 2>/dev/null
    mpris_thumb "${player}" &
  else
    # Colorize fallback icon (cache in temp location to compare)
    local temp_colored="${HYPR_CACHE_HOME}/landing/hypr-colored.tmp.png"
    colorize_fallback_icon "$temp_colored"
    if ! cmp -s "$temp_colored" "${THUMB}.png"; then
      mv "$temp_colored" "${THUMB}.png"
      reload_hyprlock
    fi
    set_mpris_blurred_empty "${THUMB}.blurred.png"
  fi
}

fn_art() {
  echo "${HYPR_CACHE_HOME}/landing/mpris.art"
}

fn_update_art() {
  # Ensures album art is fetched and cached
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  THUMB="${HYPR_CACHE_HOME}/landing/mpris"
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    mpris_thumb "${player}"
  else
    rm -f "${THUMB}".lnk "${THUMB}".art 2>/dev/null
    local temp_colored="${HYPR_CACHE_HOME}/landing/hypr-colored.tmp.png"
    colorize_fallback_icon "${temp_colored}"
    if [ -f "${temp_colored}" ]; then
      if ! cmp -s "${temp_colored}" "${THUMB}.png"; then
        mv "${temp_colored}" "${THUMB}.png"
        reload_hyprlock
      else
        rm -f "${temp_colored}"
      fi
    fi
    set_mpris_blurred_empty "${THUMB}.blurred.png"
  fi
}
