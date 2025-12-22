#!/usr/bin/env bash

#// Check if wlogout is already running

if pgrep -x "wlogout" >/dev/null; then
  pkill -x "wlogout"
  exit 0
fi

#// set file variables

scrDir=$(dirname "$(realpath "$0")")
# shellcheck disable=SC1091
source "$scrDir/globalcontrol.sh"
[ -n "${1}" ] && wlogoutStyle="${1}"
wlogoutStyle=${wlogoutStyle:-$WLOGOUT_STYLE}
confDir="${confDir:-$HOME/.config}"
wLayout="${confDir}/wlogout/layout_${wlogoutStyle}"
wlTmplt="${confDir}/wlogout/style_${wlogoutStyle}.css"
echo "wlogoutStyle: ${wlogoutStyle}"
echo "wLayout: ${wLayout}"
echo "wlTmplt: ${wlTmplt}"

if [ ! -f "${wLayout}" ] || [ ! -f "${wlTmplt}" ]; then
  echo "ERROR: Config ${wlogoutStyle} not found..."
  wlogoutStyle=1
  wLayout="${confDir}/wlogout/layout_${wlogoutStyle}"
  wlTmplt="${confDir}/wlogout/style_${wlogoutStyle}.css"
fi

#// detect monitor res

x_mon=$(hyprctl -j monitors | jq '.[] | select(.focused==true) | .width')
y_mon=$(hyprctl -j monitors | jq '.[] | select(.focused==true) | .height')
hypr_scale=$(hyprctl -j monitors | jq '.[] | select (.focused == true) | .scale' | sed 's/\.//')
#// scale config layout and style

case "${wlogoutStyle}" in
  1)
    wlColms=6
    export mgn=$((y_mon * 28 / hypr_scale))
    export hvr=$((y_mon * 23 / hypr_scale))
    ;;
  2)
    wlColms=2
    export x_mgn=$((x_mon * 35 / hypr_scale))
    export y_mgn=$((y_mon * 25 / hypr_scale))
    export x_hvr=$((x_mon * 32 / hypr_scale))
    export y_hvr=$((y_mon * 20 / hypr_scale))
    ;;
esac

#// scale font size

export fntSize=$((y_mon * 2 / 100))

#// detect wallpaper brightness

cacheDir="${HYPR_CACHE_HOME}"
WALLPAPER_CURRENT_DIR="${WALLPAPER_CURRENT_DIR:-${cacheDir}/wallpaper/current}"
dcol_mode="${dcol_mode:-dark}"
BtnCol="${BtnCol:-}"
wal_cache="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
wal_background=""

if [ -r "${wal_cache}/colors.json" ]; then
  wal_background="$(jq -r '.special.background // empty' "${wal_cache}/colors.json")"
fi

if [ -z "${wal_background}" ] && [ -r "${wal_cache}/colors.sh" ]; then
  # shellcheck disable=SC1090
  source "${wal_cache}/colors.sh"
  wal_background="${background:-}"
fi

if [ -n "${wal_background}" ]; then
  hex="${wal_background#\#}"
  if [[ "${#hex}" -ge 6 ]]; then
    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))
    luma=$(((r * 299 + g * 587 + b * 114) / 1000))
    if [ "${luma}" -lt 128 ]; then
      BtnCol="white"
    else
      BtnCol="black"
    fi
  fi
fi

#  Theme mode: detects the color-scheme set in hypr.theme and falls back if nothing is parsed.
enableWallDcol="${enableWallDcol:-1}"
if [ -z "${BtnCol}" ]; then
  if [ "${enableWallDcol}" -eq 0 ]; then
    HYPR_THEME_DIR="${HYPR_THEME_DIR:-$confDir/hypr/themes/$HYPR_THEME}"
    dcol_mode=$(get_hyprConf "COLOR_SCHEME")
    dcol_mode=${dcol_mode#prefer-}
  fi
  { [ "${dcol_mode}" == "dark" ] && BtnCol="white"; } || BtnCol="black"
fi
export BtnCol

#// eval hypr border radius

hypr_border="${hypr_border:-10}"
export active_rad=$((hypr_border * 5))
export button_rad=$((hypr_border * 8))

#// eval config files

wlStyle="$(envsubst <"${wlTmplt}")"

#// launch wlogout

wlogout -b "${wlColms}" -c 0 -r 0 -m 0 --layout "${wLayout}" --css <(echo "${wlStyle}") --protocol layer-shell
