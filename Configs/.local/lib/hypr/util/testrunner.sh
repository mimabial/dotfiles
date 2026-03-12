#!/usr/bin/env bash

scrDir="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${scrDir}/../globalcontrol.sh"
rofDir="${XDG_CONFIG_HOME}/rofi"

if [ "${1}" == "--verbose" ] || [ "${1}" == "-v" ]; then

    case ${enableWallDcol} in
    0) colorModeStatus="theme colors only" ;;
    1) colorModeStatus="auto from wallpaper brightness" ;;
    2) colorModeStatus="forced dark mode" ;;
    3) colorModeStatus="forced light mode" ;;
    esac

    echo -e "\n\ncurrent theme :: \"${HYPR_THEME}\" :: \"$(readlink "${HYPR_THEME_DIR}/wall.set")\""
    echo -e "color mode status :: ${enableWallDcol} :: ${colorModeStatus}\n"
    get_themes

    for x in "${!thmList[@]}"; do
        echo -e "\nTheme $((x + 1)) :: \${thmList[${x}]}=\"${thmList[x]}\" :: \${thmWall[${x}]}=\"${thmWall[x]}\"\n"
        get_hashmap "$(dirname "${HYPR_THEME_DIR}")/${thmList[x]}" --verbose
        echo -e "\n"
    done

    exit 0
fi
