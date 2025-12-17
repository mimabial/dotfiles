#!/bin/bash

# shellcheck source=$HOME/.local/bin/hyprshell
# shellcheck disable=SC1091
if ! source "$(which hyprshell)"; then
  echo "Error: hyprshell not found."
  exit 1
fi

if [[ -z "${XDG_CONFIG_HOME:-}" ]]; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi
if [[ -z "${XDG_CACHE_HOME:-}" ]]; then
  export XDG_CACHE_HOME="$HOME/.cache"
fi
if [[ -z "${XDG_DATA_HOME:-}" ]]; then
  export XDG_DATA_HOME="$HOME/.local/share"
fi

scrDir=${scrDir:-$HOME/.local/lib/hypr}
confDir="${confDir:-$XDG_CONFIG_HOME}"
cacheDir="${HYPR_CACHE_HOME:-"${XDG_CACHE_HOME}/hypr"}"
WALLPAPER="${cacheDir}/wall.set"
HYPRLOCK_SCOPE_NAME="${XDG_SESSION_DESKTOP:-unknown}-lockscreen.scope"

USAGE() {
  cat <<EOF
    Usage: $(basename "${0}") --[arg]

    arguments:
      --background -b    - Converts and ensures background to be a png
      --title            - Returns MPRIS song title
      --artist           - Returns MPRIS artist name
      --source           - Returns MPRIS player icon
      --status           - Returns MPRIS play/pause status icon
      --length           - Returns MPRIS song length (MM:SS)
      --profile          - Generates the profile picture
      --cava             - Placeholder function for cava
      --art              - Prints the path to the mpris art
      --select      -S   - Selects the hyprlock layout
      --help       -h    - Displays this help message
EOF
}

# Converts and ensures background to be a png
fn_background() {
  local wp bg bg_tmp mime cached_thumb is_video
  wp="$(realpath "${WALLPAPER}" 2>/dev/null)" || return 1
  bg="${cacheDir}/wall.set.png"
  bg_tmp="${cacheDir}/.wall.set.tmp.${$}.png"
  mkdir -p "${cacheDir}"

  mime="$(file --mime-type -b "${wp}" 2>/dev/null || true)"
  is_video=$(grep -c '^video/' <<<"${mime}")
  if [ "${is_video}" -eq 1 ]; then
    print_log -sec "wallpaper" -stat "converting video" "${wp}"
    mkdir -p "${cacheDir}/wallpapers/thumbnails"
    cached_thumb="${cacheDir}/wallpapers/$(${hashMech:-sha1sum} "${wp}" | cut -d' ' -f1).png"
    extract_thumbnail "${wp}" "${cached_thumb}"
    wp="${cached_thumb}"
  fi

  mime="$(file --mime-type -b "${wp}" 2>/dev/null || true)"
  # Convert synchronously to ensure hyprlock has a complete image (hyprlock expects PNG)
  if [[ "${mime}" == "image/png" ]]; then
    cp -f "${wp}" "${bg_tmp}"
  else
    magick "${wp}[0]" "png:${bg_tmp}"
  fi
  mv -f "${bg_tmp}" "${bg}"
}

# Convert .face.icon to PNG if needed
ensure_face_icon_png() {
  local face_icon="$HOME/.face.icon"

  # Check if .face.icon exists
  [ ! -f "$face_icon" ] && return 1

  # Check if it's already a PNG using file command
  local file_type=$(file -b "$face_icon")
  if [[ "$file_type" =~ ^PNG ]]; then
    # Already PNG, no conversion needed
    return 0
  fi

  # Not a PNG, convert it
  magick "${face_icon}[0]" "png:${face_icon}.tmp.png" 2>/dev/null || return 1
  mv -f "${face_icon}.tmp.png" "$face_icon" || return 1
  return 0
}

# Colorize fallback icon with pywal colors
colorize_fallback_icon() {
  local output_path="$1"
  local source_icon="$XDG_DATA_HOME/icons/Pywal16-Icon/hypr.png"

  # Get pywal colors
  local color_file="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.sh"
  if [ ! -f "$color_file" ]; then
    # No colors available, just copy
    cp "$source_icon" "$output_path"
    return
  fi

  # Source colors
  source "$color_file"

  # Apply colorization - tint the icon while preserving detail
  # Modulate reduces saturation and colorize adds a stronger tint
  magick "$source_icon" \
    -modulate 100,60,100 \
    -fill "${color4:-#458588}" -colorize 60% \
    "$output_path"
}

fn_profile() {
  local profile_dir="${cacheDir}/landing"
  local profile_png="${profile_dir}/profile.png"
  local face_icon="$HOME/.face.icon"

  mkdir -p "${profile_dir}"

  if [[ -f "${face_icon}" ]]; then
    if ensure_face_icon_png; then
      if [[ ! -f "${profile_png}" ]] || [[ "${face_icon}" -nt "${profile_png}" ]] || ! cmp -s "${face_icon}" "${profile_png}"; then
        cp -f "${face_icon}" "${profile_png}"
      fi
    fi
  fi

  # Ensure profile image exists so layouts don't show a blank avatar
  if [[ ! -f "${profile_png}" ]]; then
    colorize_fallback_icon "${profile_png}"
  fi
  return 0
}

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
  THUMB="${cacheDir}/landing/mpris"

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
    magick "${THUMB}.art" -quality 50 "${THUMB}.png" 2>/dev/null || return 1
    # Create blurred version - use physical monitor resolution (hyprlock handles scaling with fractional_scaling=1)
    local monitor_info=$(hyprctl monitors -j | jq -r '.[0] | "\(.width)x\(.height)"')
    local width=$(echo "$monitor_info" | cut -d'x' -f1)
    local height=$(echo "$monitor_info" | cut -d'x' -f2)
    magick "${THUMB}.art" -blur 20x3 -resize ${width}x^ -gravity center -extent ${width}x${height}\! "${THUMB}.blurred.png" 2>/dev/null

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
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    playerctl -p "${player}" metadata --format "{{xesam:title}}" 2>/dev/null
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
  # Legacy function - combined text format for backward compatibility
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  THUMB="${cacheDir}/landing/mpris"
  WALL="${cacheDir}/wall.set"
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]]; then
    playerctl -p "${player}" metadata --format "{{xesam:title}} $(mpris_icon "${player}")  {{xesam:artist}}" 2>/dev/null
    mpris_thumb "${player}" &
  else
    # Colorize fallback icon (cache in temp location to compare)
    local temp_colored="${cacheDir}/landing/hypr-colored.tmp.png"
    colorize_fallback_icon "$temp_colored"
    if ! cmp -s "$temp_colored" "${THUMB}.png"; then
      mv "$temp_colored" "${THUMB}.png"
      reload_hyprlock
    fi
    # Use normal wallpaper as fallback (no blur)
    if [ ! -f "${THUMB}.blurred.png" ]; then
      cp -f "${WALL}.png" "${THUMB}.blurred.png" 2>/dev/null
      reload_hyprlock
    fi
  fi
}

fn_cava() {
  local tempFile=/tmp/hyprlock-cava
  [ -f "${tempFile}" ] && tail -n 1 "${tempFile}"
  config_file="${XDG_RUNTIME_DIR}/cava.hyprlock"
  if [ "$(pgrep -c -f "cava -p ${config_file}")" -eq 0 ]; then
    trap 'rm -f ${tempFile}' EXIT
    "$scrDir/cava.sh" hyprlock >${tempFile} 2>&1
  fi
}

fn_art() {
  echo "${cacheDir}/landing/mpris.art"
}

fn_update_art() {
  # Ensures album art is fetched and cached
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  THUMB="${cacheDir}/landing/mpris"
  WALL="${cacheDir}/wall.set"
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"

  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    mpris_thumb "${player}"
  else
    rm -f "${THUMB}".lnk "${THUMB}".art 2>/dev/null
    colorize_fallback_icon "${THUMB}.png"
    # Use normal wallpaper as fallback (no blur)
    cp -f "${WALL}.png" "${THUMB}.blurred.png" 2>/dev/null
    reload_hyprlock
  fi
}

find_filepath() {
  local filename="${*:-$1}"
  local search_dirs=(
    "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprlock"
    "${HYPRLOCK_CONF_DIR}"
  )
  print_log -sec "hyprlock" -stat "Searching for layout" "$filename"
  find "${search_dirs[@]}" -type f -name "${filename}*" 2>/dev/null | head -n 1
}

check_and_sanitize_process() {
  local unit_name="${1:-${HYPRLOCK_SCOPE_NAME}}"
  if systemctl --user is-active "${unit_name}" >/dev/null 2>&1; then
    systemctl --user stop "${unit_name}" >/dev/null 2>&1
  fi
}

reload_hyprlock() {
  local unit_name="${2:-${HYPRLOCK_SCOPE_NAME}}"

  if systemctl --user is-active "${unit_name}" >/dev/null 2>&1; then
    systemctl --user kill -s USR2 "${HYPRLOCK_SCOPE_NAME}" >/dev/null 2>&1
  else
    pkill -USR2 hyprlock >/dev/null 2>&1
  fi
}

append_label_to_file() {
  local file="${1}"

  cat <<EOF >>"${file}"
label {
  text = PREVIEW! Press a key or swipe to exit.
  color = rgba(\$wallbash_txt122)
  font_size = 50
  position = 0, 0
  halign = center
  valign = top
  zindex = 6
}

label {
  text = PREVIEW! Press a key or swipe to exit.
  color = rgba(\$wallbash_txt122)
  font_size = 50
  position = 0, 0
  halign = center
  valign = bottom
  zindex = 6
}

label {
  text = PREVIEW! Press a key or swipe to exit.
  color = rgba(\$wallbash_txt122)
  font_size = 50
  position = 0, 0
  halign = center
  valign = center
  zindex = 6
}

EOF
}

layout_test() {
  print_log -sec "hyprlock" -stat "Test" "Please swipe,press a key or click to exit."
  local hyprlock_conf_name="${*:-${1}}"
  if [[ "${hyprlock_conf_name}" == "Theme Preference" ]]; then
    hyprlock_conf_name="theme"
  fi
  check_and_sanitize_process
  hyprlock_conf_path=$(find_filepath "${hyprlock_conf_name}")
  if [ -z "${hyprlock_conf_path}" ]; then
    print_log -sec "hyprlock" -stat "Error" "Layout ${hyprlock_conf_name} not found."
    exit 1
  fi
  sleep 2
  local temp_path="${XDG_RUNTIME_DIR}/hyprlock-test.conf"
  generate_conf "${hyprlock_conf_path}" "${temp_path}"
  append_label_to_file "${temp_path}"
  app2unit.sh -S both -u "${HYPRLOCK_SCOPE_NAME}" -t scope -- hyprlock --no-fade-in --immediate-render --grace 99999999 -c "${temp_path}"
  rm -f "${temp_path}"
}

rofi_test_preview() {
  local hyprlock_conf_name="${*:-${1}}"
  if [[ "${hyprlock_conf_name}" == "Theme Preference" ]]; then
    hyprlock_conf_name="theme"
  fi
  local unit_name="${XDG_SESSION_DESKTOP:-unknown}-lockscreen-preview.scope"
  check_and_sanitize_process "${unit_name}"
  send_notifs "Hyprlock layout: ${hyprlock_conf_name}" "Please swipe, press a key or click to exit." \
    -i "system-lock-screen" -t 3000 \
    -r 9
  app2unit.sh -S both -u "${unit_name}" -t scope -- hyprlock.sh --test "${hyprlock_conf_name}"
}

generate_conf() {
  local path="${1:-$confDir/hypr/hyprlock/theme.conf}"
  local target_file="${2:-$confDir/hypr/hyprlock.conf}"
  local hyprlock_conf=${SHARE_DIR:-$XDG_DATA_HOME}/hypr/hyprlock.conf

  cat <<CONF >"${target_file}"
#! █░█ █▄█ █▀█ █▀█ █░░ █▀█ █▀▀ █▄▀
#! █▀█ ░█░ █▀▀ █▀▄ █▄▄ █▄█ █▄▄ █░█


#*┌────────────────────────────────────────────────────────────────────────────┐
#*│    Hyprlock Configuration File                                          │
#*│ # Please do not edit this file manually.                                   │
#*│ # Follow the instructions below on how to make changes.                    │
#*│                                                                            │
#*└────────────────────────────────────────────────────────────────────────────┘

\$LAYOUT_PATH=${path}

source = ${hyprlock_conf}

CONF
}

# hyprlock selector
fn_select() {
  # Set rofi scaling
  font_scale="${ROFI_HYPRLOCK_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  # set font name
  font_name=${ROFI_HYPRLOCK_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}

  # set rofi font override
  font_override="* {font: \"${font_name} ${font_scale}\";}"

  # Window and element styling
  hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
  wind_border=$((hypr_border * 3 / 2))
  elem_border=$((hypr_border == 0 ? 5 : hypr_border))
  hypr_width=${hypr_width:-"$(hyprctl -j getoption general:border_size | jq '.int')"}
  r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;} wallbox{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"

  # List available .conf files in hyprlock directory
  layout_dir="$confDir/hypr/hyprlock"
  layout_items=$(find -L "${layout_dir}" -name "*.conf" ! -name "theme.conf" 2>/dev/null | sed 's/\.conf$//')

  if [ -z "$layout_items" ]; then
    notify-send -i "preferences-desktop-display" "Error" "No .conf files found in ${layout_dir}"
    exit 1
  fi

  layout_items="Theme Preference
${layout_items}"

  selected_layout=$(awk -F/ '{print $NF}' <<<"$layout_items" \
    | rofi -dmenu -i -select "${HYPRLOCK_LAYOUT}" \
      -p "Select hyprlock layout" \
      -theme-str "entry { placeholder: \"🔒 Hyprlock Layout...\"; }" \
      -theme-str "${font_override}" \
      -theme-str "${r_override}" \
      -theme-str "$(get_rofi_pos)" \
      -on-selection-changed "hyprshell hyprlock.sh --test-preview  \"{entry}\"" \
      -theme "${ROFI_HYPRLOCK_STYLE:-clipboard}")

  if [ -z "$selected_layout" ]; then
    echo "No selection made"
    exit 0
  fi

  set_conf "HYPRLOCK_LAYOUT" "${selected_layout}"
  if [ "$selected_layout" == "Theme Preference" ]; then
    selected_layout="theme"
  fi
  local hyprlock_conf_path
  hyprlock_conf_path=$(find_filepath "${selected_layout}")
  generate_conf "$hyprlock_conf_path"
  "${scrDir}/font.sh" resolve "$hyprlock_conf_path"
  fn_profile

  # Notify the user
  notify-send -i "system-lock-screen" "Hyprlock layout:" "${selected_layout}"
}

if [ -z "${*}" ]; then
  if [[ ! -f "${cacheDir}/wall.set.png" ]] || ! file -b "${cacheDir}/wall.set.png" 2>/dev/null | grep -q '^PNG'; then
    fn_background || true
  fi

  if [ ! -f "${cacheDir}/wallpapers/hyprlock.png" ]; then
    print_log -sec "hyprlock" -stat "setting" " ${cacheDir}/wallpapers/hyprlock.png"
    "${scrDir}/wallpaper.sh" -s "$(readlink "${HYPR_THEME_DIR}/wall.set")" --backend hyprlock
  fi
  # Ensure MPRIS fallback wallpaper exists before launching hyprlock
  THUMB="${cacheDir}/landing/mpris"
  if [[ ! -f "${THUMB}.blurred.png" ]] || ! file -b "${THUMB}.blurred.png" 2>/dev/null | grep -q '^PNG'; then
    cp -f "${cacheDir}/wall.set.png" "${THUMB}.blurred.png" 2>/dev/null
  fi
  # Auto-update profile if .face.icon changed
  fn_profile
  check_and_sanitize_process
  app2unit.sh -u "${HYPRLOCK_SCOPE_NAME}" -t scope -- hyprlock
  exit 0
fi

# Update MPRIS thumbnail in background for all MPRIS-related calls
case "$1" in
  --source)
    # Only update art if last update was >2 seconds ago
    LOCK_FILE="/tmp/hyprlock-art.lock"
    if [ ! -f "$LOCK_FILE" ] || [ $(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0))) -gt 2 ]; then
      touch "$LOCK_FILE"
      (fn_update_art) &
    fi
    ;;
esac

# Define long options
LONGOPTS="select,background,profile,title,artist,source,status,length,update-art,cava,art,help,test:,test-preview:"

# Parse options
PARSED=$(getopt --options Shb --longoptions $LONGOPTS --name "$0" -- "$@")
if [ $? -ne 0 ]; then
  exit 2
fi

# Apply parsed options
eval set -- "$PARSED"

while true; do
  case "$1" in
    --test)
      layout_test "${2}"
      exit 0
      ;;
    --test-preview)
      rofi_test_preview "${2}"
      exit 0
      ;;
    select | -S | --select)
      fn_select
      exit 0
      ;;
    background | --background | -b)
      fn_background
      exit 0
      ;;
    profile | --profile)
      fn_profile
      exit 0
      ;;
    --title)
      fn_title
      exit 0
      ;;
    --artist)
      fn_artist
      exit 0
      ;;
    --source)
      fn_source
      exit 0
      ;;
    --status)
      fn_status
      exit 0
      ;;
    --length)
      fn_length
      exit 0
      ;;
    --update-art)
      fn_update_art
      exit 0
      ;;
    cava | --cava)
      fn_cava
      exit 0
      ;;
    art | --art)
      fn_art
      exit 0
      ;;
    help | --help | -h)
      USAGE
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
  shift
done
