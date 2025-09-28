#! /bin/bash

# shellcheck source=$HOME/.local/bin/hyde-shell
# shellcheck disable=SC1091
if ! source "$(which hyde-shell)"; then
  echo "Error: hyde-shell not found."
  echo "Is HaLL installed?"
  exit 1
fi
scrDir=${scrDir:-$HOME/.local/lib/hyde}
confDir="${confDir:-$XDG_CONFIG_HOME}"
cacheDir="${HYDE_CACHE_HOME:-"${XDG_CACHE_HOME}/hyde"}"
WALLPAPER="${cacheDir}/wall.set"

USAGE() {
  cat <<EOF
    Usage: $(basename "${0}") --[arg]

    arguments:
      --background -b    - Converts and ensures background to be a png
                            : \$BACKGROUND_PATH
      --mpris <player>   - Handles metadata retrieval
                            : \$MPRIS_TEXT
      --image <player>   - Handles mpris thumbnail generation
                            : \$MPRIS_IMAGE
      --profile          - Generates the profile picture
                            : \$PROFILE_IMAGE
      --cava             - Placeholder function for cava
                            : \$CAVA_CMD
      --art              - Prints the path to the mpris art"
                            : \$MPRIS_ART
      --select      -s     - Selects the hyprlock layout"
                            : \$LAYOUT_PATH
      --help       -h    - Displays this help message"
EOF
}

# Converts and ensures background to be a png
fn_background() {
  WP="$(realpath "${WALLPAPER}")"
  BG="${cacheDir}/wall.set.png"

  is_video=$(file --mime-type -b "${WP}" | grep -c '^video/')
  if [ "${is_video}" -eq 1 ]; then
    print_log -sec "wallpaper" -stat "converting video" "$WP"
    mkdir -p "${HYDE_CACHE_HOME}/wallpapers/thumbnails"
    cached_thumb="$HYDE_CACHE_HOME/wallpapers/$(${hashMech:-sha1sum} "${WP}" | cut -d' ' -f1).png"
    extract_thumbnail "${WP}" "${cached_thumb}"
    WP="${cached_thumb}"
  fi

  cp -f "${WP}" "${BG}"
  mime=$(file --mime-type "${WP}" | grep -E "image/(png|jpg|webp)")
  #? Run this in the background because converting takes time
  ([[ -z ${mime} ]] && magick "${BG}"[0] "${BG}") &
}

fn_profile() {
  local profilePath="${cacheDir}/landing/profile"
  mpris_fallback_image "${profilePath}.png"
  return 0
}

fn_mpris() {
  local mode="${1:-full}"  # full, title, artist, source
  local player=${2:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  THUMB="${cacheDir}/landing/mpris"
  # Check if playerctl is available
  if ! command -v playerctl >/dev/null 2>&1; then
    return 1
  fi
  # Check if any players are available
  if [ -z "$player" ]; then
    return 1
  fi
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"
  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    case "$mode" in
      "title")
        playerctl -p "${player}" metadata --format "{{xesam:title}}"
        ;;
      "artist") 
        playerctl -p "${player}" metadata --format "{{xesam:artist}}"
        ;;
      "length")
        length=playerctl -p "${player}" metadata --format "{{xesam:length}}"
        if [ "$length" ]; then
          local seconds=$((length / 1000000))
          local minutes=$((seconds / 60))
          local remaining_seconds=$((seconds % 60))
          printf "%d:%02d m" $minutes $remaining_seconds
        fi
        ;;
      "source")
        mpris_icon "${player}"
        ;;
      "status")
        "${player_status}"
        ;;
      *)
        # Full format with length limit
        title=$(playerctl -p "${player}" metadata --format "{{xesam:title}}" 2>/dev/null | head -c 25)
        artist=$(playerctl -p "${player}" metadata --format "{{xesam:artist}}" 2>/dev/null | head -c 20)
        icon=$(mpris_icon "${player}")
        if [ -n "$title" ] && [ -n "$artist"]; then
          echo "${title} ${icon} ${artist}"
        elif [ -n "$title" ]; then
          echo "${title} ${icon}"
        else
          echo "${icon} ${player}"
        fi
        ;;
    esac
    mpris_thumb "${player}" "${THUMB}"
  else
    case "$mode" in
      "title")
        echo "$USER"
        ;;
      "artist")
        echo "$(hyprctl splash)"
        ;;
      *)
        echo ""
        ;;
    esac
    # Clear the link file when music stops
    rm -f "${THUMB}.lnk" 2>/dev/null
    mpris_fallback_image "${THUMB}.png"
    return 1
  fi
}

mpris_icon() {

  local player=${1:-default}
  declare -A player_dict=(
    ["default"]=""
    ["spotify"]=""
    ["YoutubeMusic"]=""
    ["librewolf"]=""
    ["vlc"]="嗢"
    ["chromium"]=""
  )

  for key in "${!player_dict[@]}"; do
    if [[ ${player} == "$key"* ]]; then
      echo "${player_dict[$key]}"
      return
    fi
  done
  echo "" # Default icon if no match is found

}

fn_image() {
  local player=${1:-$(playerctl --list-all 2>/dev/null | head -n 1)}
  THUMB="${cacheDir}/landing/mpris"
  player_status="$(playerctl -p "${player}" status 2>/dev/null)"
  if [[ "${player_status}" == "Playing" ]] || [[ "${player_status}" == "Paused" ]]; then
    mpris_thumb "${player}" "${THUMB}"
  else
    mpris_fallback_image "${THUMB}.png"
  fi
}

mpris_thumb() { # Generate thumbnail for mpris
  local player=${1:-""}
  local THUMB="${2:-${THUMB}}"
  local output_file="${THUMB}.png"
  local blurred_file="${THUMB}-blurred.png"
  local lock_file="${THUMB}.lock"
  local link_file="${THUMB}.lnk"
  local temp_art="${THUMB}.art"
  artUrl=$(playerctl -p "${player}" metadata --format '{{mpris:artUrl}}' 2>/dev/null)
  [ "${artUrl}" == "$(cat "$link_file")" ] && [ -f "$output_file" ] && exit 0
  if [ -z "$artUrl" ] || [ "$artUrl" == "file://" ]; then
    mpris_fallback_image "$output_file"
    return 0
  fi
  [ -f "$lock_file" ] && return 0
  touch "$lock_file"
  {
    echo "$artUrl" > "$link_file"
    if curl -Lso "$temp_art" "$artUrl" --max-time 5; then
      magick "$temp_art" -quality 50 "$output_file"
      # Create blurred version
      magick "$output_file" -blur 200x7 -resize 1920x^ -gravity center -extent 1920x1080\! "$blurred_file"
      rm -f "$temp_art"
    else
      mpris_fallback_image "$output_file"
    fi
    rm -f "$lock_file"
    pkill -USR2 hyprlock >/dev/null 2>&1
  } &
}

mpris_fallback_image() {
  local target_file="${1:-${THUMB}.png}"
  local blurred_file="${THUMB}-blurred.png"
  local source_file=""

  # Clear the link file since we're using fallback
  rm -f "${THUMB}.lnk" 2>/dev/null
  
  # Priority order for fallback images
  if [ -f "$HOME/.face.icon" ]; then
    source_file="$HOME/.face.icon"
  elif [ -f "$XDG_DATA_HOME/icons/Wallbash-Icon/hyde.png" ]; then
      source_file="$XDG_DATA_HOME/icons/Wallbash-Icon/hyde.png"
  elif [ -f "/usr/share/pixmaps/default-user.png" ]; then
    source_file="/usr/share/pixmaps/default-user.png"
  fi

  if [ -f "$source_file" ]; then
    if ! magick "$source_file" -resize 256x256^ -gravity center -extent 256x256 "$target_file" 2>/dev/null; then
      magick -size 256x256 xc:'#313244' -fill '#cdd6f4' -pointsize 100 -gravity center -annotate +0+0 'f' "$target_file" 2>/dev/null
      # Create blured version
      magick "$target_file" -blur 200x7 -resize 1920x^ -gravity center -extent 1920x1080\! "$blurred_file"
      pkill -USR2 hyprlock >/dev/null 2>&1
    fi
  fi
}

fn_cava() {
  local tempFile=/tmp/hyprlock-cava
  [ -f "${tempFile}" ] && tail -n 1 "${tempFile}"
  config_file="$HYDE_RUNTIME_DIR/cava.hyprlock"
  if [ "$(pgrep -c -f "cava -p ${config_file}")" -eq 0 ]; then
    trap 'rm -f ${tempFile}' EXIT
    "$scrDir/cava.sh" hyprlock >${tempFile} 2>&1
  fi
}

fn_art() {
  echo "${cacheDir}/landing/mpris.art"
}

# hyprlock selector
fn_select() {
  # Set rofi scaling
  font_scale="${ROFI_HYPRLOCK_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  # set font name
  font_name=${ROFI_HYPRLOCK_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}

  # set rofi font override
  font_override="* {font: \"${font_name:-"JetBrainsMono Nerd Font"} ${font_scale}\";}"

  # Window and element styling
  hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
  wind_border=$((hypr_border * 3 / 2))
  elem_border=$((hypr_border == 0 ? 5 : hypr_border))
  hypr_width=${hypr_width:-"$(hyprctl -j getoption general:border_size | jq '.int')"}
  r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;} wallbox{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"

  # List available .conf files in hyprlock directory
  layout_dir="$confDir/hypr/hyprlock"
  layout_items=$(find "${layout_dir}" -name "*.conf" ! -name "theme.conf" 2>/dev/null | sed 's/\.conf$//')

  if [ -z "$layout_items" ]; then
    notify-send -i "preferences-desktop-display" "Error" "No .conf files found in ${layout_dir}"
    exit 1
  fi

  layout_items="Theme Preference
$layout_items"

  selected_layout=$(awk -F/ '{print $NF}' <<<"$layout_items" |
    rofi -dmenu -i -select "${HYPRLOCK_LAYOUT}" \
      -p "Select hyprlock layout" \
      -theme-str "entry { placeholder: \"🔒 Hyprlock Layout...\"; }" \
      -theme-str "${font_override}" \
      -theme-str "${r_override}" \
      -theme-str "$(get_rofi_pos)" \
      -theme "${ROFI_HYPRLOCK_STYLE:-clipboard}")
  if [ -z "$selected_layout" ]; then
    echo "No selection made"
    exit 0
  fi
  set_conf "HYPRLOCK_LAYOUT" "${selected_layout}"
  if [ "$selected_layout" == "Theme Preference" ]; then
    selected_layout="theme"
  fi
  generate_conf "${layout_dir}/${selected_layout}.conf"
  "${scrDir}/font.sh" resolve "${layout_dir}/${selected_layout}.conf"
  fn_profile

  # Notify the user
  notify-send -i "system-lock-screen" "Hyprlock layout:" "${selected_layout}"

}

generate_conf() {
  local path="${1:-$confDir/hypr/hyprlock/theme.conf}"
  local hyde=${SHARE_DIR:-$XDG_DATA_HOME}/hyde/hyprlock.conf

  cat <<CONF >"$confDir/hypr/hyprlock.conf"
#! █░█ █▄█ █▀█ █▀█ █░░ █▀█ █▀▀ █▄▀
#! █▀█ ░█░ █▀▀ █▀▄ █▄▄ █▄█ █▄▄ █░█


#*┌────────────────────────────────────────────────────────────────────────────┐
#*│    Hyprlock Configuration File                                           │
#*│ # Please do not edit this file manually.                                   │
#*│ # Follow the instructions below on how to make changes.                    │
#*│                                                                            │
#*└────────────────────────────────────────────────────────────────────────────┘



#*┌──────────────────────────────────────────────────────────────────────────┐
#*│ #* Hyprlock active layout path:                                          │
#*│ # Set the layout path to be used by Hyprlock.                            │
#*│ # Check the available layouts in the './hyprlock/' directory.            │
#*│ # Example: /$LAYOUT_PATH=/path/to/Arfan on Clouds.conf                   │
#*└──────────────────────────────────────────────────────────────────────────┘

\$LAYOUT_PATH=${path}


#*┌────────────────────────────────────────────────────────────────────────────┐
#*│    Persistent layout declaration                                         │
#*│ # If a persistent layout path is declared in                               │
#*│ \$XDG_CONFIG_HOME/hypr/hyde.conf,                                          │
#*│ # the above layout setting will be ignored.                                │
#*│ # this should be the full path to the layout file.                         │
#*│                                                                            │
#*└────────────────────────────────────────────────────────────────────────────┘


#*┌──────────────────────────────────────────────────────────────────────────┐
#*│    All boilerplate configurations are handled by HaLL                  │
#*└──────────────────────────────────────────────────────────────────────────┘

source = ${hyde_hyprlock_conf}


#┌────────────────────────────────────────────────────────────────────────────┐
#│ Making a custom layout                                                   │
#│ - To create a custom layout, make a file in the './hyprlock/' directory.   │
#│ - Example: './hyprlock/your_custom.conf'                                   │
#│ - To use the custom layout, set the following variable:                    │
#│ - \$LAYOUT_PATH=your_custom                                                │
#│ - The custom layout will be sourced automatically.                         │
#│ - Alternatively, you can statically source the layout in                   │
#│          '~/.config/hypr/hyde.conf'.                                       │
#│ - This will take precedence over the variable in                           │
#│            '~/.config/hypr/hyprlock.conf'.                                 │ 
#│                                                                            │
#└────────────────────────────────────────────────────────────────────────────┘


#┌────────────────────────────────────────────────────────────────────────────┐
#│  Command Variables                                                       │
#│ # Hyprlock ships with there default variables that can be used to          │
#│ customize the lock screen.                                                 │
#│ https://wiki.hyprland.org/Hypr-Ecosystem/hyprlock/#label                   │
#│                                                                            │
#└────────────────────────────────────────────────────────────────────────────┘

#┌────────────────────────────────────────────────────────────────────────────┐
#│ HaLL also provides custom variables to extend hyprlock's functionality.  │
#│                                                                            │
#│   \$BACKGROUND_PATH                                                        │
#│   - The path to the wallpaper image.                                       │
#│                                                                            │
#│   \$HYPRLOCK_BACKGROUND                                                    │
#│   - The path to the static hyprlock wallpaper image.                       │
#│   - Can be set to set a static wallpaper for Hyprlock.                     │
#│                                                                            │
#│   \$MPRIS_IMAGE                                                            │
#│   - The path to the MPRIS image.                                           │
#│   - If MPRIS is not available, it will show the ~/.face.icon image         │
#│   - if available, otherwise, it will show the HaLL logo.                   │
#│                                                                            │
#│   \$PROFILE_IMAGE                                                          │
#│   - The path to the profile image.                                         │
#│   - If the image is not available, it will show the ~/.face.icon image     │
#│   - if available, otherwise, it will show the HaLL logo.                   │
#│                                                                            │
#│   \$GREET_TEXT                                                             │
#│   - A greeting text to be displayed on the lock screen.                    │
#│   - The text will be updated every hour.                                   │
#│                                                                            │
#│   \$resolve.font                                                           │
#│   - Resolves the font name and download link.                              │
#│   - HaLL will run 'font.sh resolve' to install the font for you.           │
#│   - Note that you needed to have a network connection to download the      │
#│ font.                                                                      │
#│   - You also need to restart Hyprlock to apply the font.                   │
#│                                                                            │
#│   cmd [update:1000] \$MPRIS_TEXT                                           │
#│   - Text from media players in "Title  Author" format.                    │
#│                                                                            │
#│   cmd [update:1000] \$SPLASH_CMD                                           │
#│   - Outputs the song title when MPRIS is available,                        │
#│   - otherwise, it will output the splash command.                          │
#│                                                                            │
#│   cmd [update:1] \$CAVA_CMD                                                │
#│   - The command to be executed to get the CAVA output.                     │
#│   - ⚠️ (Use with caution as it eats up the CPU.)                           │
#│                                                                            │
#│   cmd [update:5000] \$BATTERY_ICON                                         │
#│   - The battery icon to be displayed on the lock screen.                   │
#│   - Only works if the battery is available.                                │
#│                                                                            │
#│   cmd [update:1000] \$KEYBOARD_LAYOUT                                      │
#│   - The current keyboard layout                                            │
#│   - SUPER + K to change the keyboard layout (or any binding you set)       │
#│                                                                            │
#└────────────────────────────────────────────────────────────────────────────┘

CONF
}

if [ -z "${*}" ]; then
  if [ ! -f "$HYDE_CACHE_HOME/wallpapers/hyprlock.png" ]; then
    print_log -sec "hyprlock" -stat "setting" " $HYDE_CACHE_HOME/wallpapers/hyprlock.png"
    "${scrDir}/wallpaper.sh" -s "$(readlink "${HYDE_THEME_DIR}/wall.set")" --backend hyprlock
  fi
  uwsm app -- hyprlock || hyprlock
  exit 0
fi

# Define long options
LONGOPTS="select,background,profile,mpris:,image,cava,art,help"

# Parse options
PARSED=$(
  if ! getopt --options shb --longoptions $LONGOPTS --name "$0" -- "$@"; then
    exit 2
  fi
)

# Apply parsed options
eval set -- "$PARSED"

while true; do
  case "$1" in
  select | -s | --select)
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
  mpris | --mpris)
    fn_mpris "${2}"
    exit 0
    ;;
  cava | --cava) # Placeholder function for cava
    fn_cava
    exit 0
    ;;
  image | --image)
    fn_image
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
