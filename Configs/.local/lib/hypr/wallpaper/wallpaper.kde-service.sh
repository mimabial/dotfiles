#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell wallpaper/wallpaper.kde-service [-t THEME -w WALLPAPER]
Install the KDE service menu that adds a wallpaper to a theme; with no options,
regenerate the menu entry from the current theme list." "$@"

hypr_runtime_require state wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1
script_path="$(realpath "$0")"
service_menu_dir="${XDG_DATA_HOME:-$HOME/.local/share}/kio/servicemenus"
service_menu_file="${service_menu_dir}/hyprwallpaper.desktop"
themes_dir="$(dirname "${HYPR_THEME_DIR}")"
selected_theme=""
selected_wallpaper=""
declare -a theme_names=() theme_wallpapers=()
theme_catalog_load_and_repair_links_into theme_names theme_wallpapers

while getopts "t:w:" option; do
  case $option in

    t)
      for theme_index in "${!theme_names[@]}"; do
        if [[ "${theme_names[theme_index]}" == "$OPTARG" ]]; then
          selected_theme="${theme_names[theme_index]}"
          break
        fi
      done
      [[ -n "${selected_theme}" ]] || { echo "Error: '$OPTARG' theme not available..."; exit 1; }
      ;;

    w)
      if [[ -f "$OPTARG" ]] && file --mime-type "$OPTARG" | grep -q 'image/'; then
        selected_wallpaper="$OPTARG"
      else
        echo "Error: '$OPTARG' is not an image file..."
        exit 1
      fi
      ;;

    *)
      selected_theme=""
      selected_wallpaper=""
      ;;

  esac
done

if [[ -n "${selected_theme}" && -n "${selected_wallpaper}" ]]; then
  theme_hashes=()
  theme_walls=()

  incoming_wallpaper_hash="$(wallpaper_file_hash "${selected_wallpaper}")"
  wallpaper_scan_hashes_into theme_hashes theme_walls "${themes_dir}/${selected_theme}"
  if [[ " ${theme_hashes[*]} " == *" ${incoming_wallpaper_hash} "* ]]; then
    send_ephemeral_notif "hypr-wallpaper-kde-error" -a "Wallpaper" -i "${WALLPAPER_THUMB_DIR}/${incoming_wallpaper_hash}.sqre" -t 3000 "Error" "Hash matched in ${selected_theme}"
    exit 0
  fi

  cp "${selected_wallpaper}" "${themes_dir}/${selected_theme}/wallpapers"
  ln -fs "${themes_dir}/${selected_theme}/wallpapers/$(basename "${selected_wallpaper}")" "${themes_dir}/${selected_theme}/wall.set"

  "${LIB_DIR}/hypr/theme/theme.switch.sh" -s "${selected_theme}"
  send_ephemeral_notif "hypr-wallpaper-kde" -a "Wallpaper" -i "${WALLPAPER_THUMB_DIR}/${incoming_wallpaper_hash}.sqre" -t 2000 "Wallpaper set in ${selected_theme}"

else

  echo -e "[Desktop Entry]\nType=Service\nMimeType=image/png;image/jpeg;image/jpg;image/gif\nActions=Menu-Refresh$(printf ";%s" "${theme_names[@]}")\nX-KDE-Submenu=Set As Wallpaper...\n\n[Desktop Action Menu-Refresh]\nName=.: Refresh List :.\nExec=${script_path}" >"${service_menu_file}"
  for theme_index in "${!theme_names[@]}"; do
    echo -e "\n[Desktop Action ${theme_names[theme_index]}]\nName=${theme_names[theme_index]}\nExec=${script_path} -t \"${theme_names[theme_index]}\" -w %u" >>"${service_menu_file}"
  done

fi
