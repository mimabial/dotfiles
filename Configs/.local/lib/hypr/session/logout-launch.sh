#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system || exit 1
hypr_runtime_load_state || exit 1

#// Check if wlogout is already running

if hypr_user_pgrep -x "wlogout" >/dev/null; then
  hypr_user_pkill -x "wlogout"
  exit 0
fi

#// set file variables

[ -n "${1:-}" ] && wlogout_style="${1}"
wlogout_style=${wlogout_style:-${WLOGOUT_STYLE:-}}
wl_layout="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout/layout_${wlogout_style}"
wl_template="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout/style_${wlogout_style}.css"
echo "wlogout_style: ${wlogout_style}"
echo "wl_layout: ${wl_layout}"
echo "wl_template: ${wl_template}"

if [ ! -f "${wl_layout}" ] || [ ! -f "${wl_template}" ]; then
  echo "ERROR: Config ${wlogout_style} not found..."
  wlogout_style=1
  wl_layout="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout/layout_${wlogout_style}"
  wl_template="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout/style_${wlogout_style}.css"
fi

#// detect monitor res

# Treat scale as fixed-point tenths so multi-decimal values like 1.25
# stay in the same sizing range as the existing 1.0/1.5/2.0 behavior.
read -r x_mon y_mon hypr_scale < <(
  hyprctl -j monitors \
    | jq -r 'first(.[] | select(.focused == true) | "\(.width) \(.height) \((.scale * 10 | round))") // empty'
)
x_mon="${x_mon:-1920}"
y_mon="${y_mon:-1080}"
hypr_scale="${hypr_scale:-10}"
[[ "${hypr_scale}" =~ ^[0-9]+$ ]] || hypr_scale=10
(( hypr_scale > 0 )) || hypr_scale=10
scale_divisor=$((hypr_scale * 10))
#// scale config layout and style

case "${wlogout_style}" in
  1)
    wl_columns=6
    export mgn=$((y_mon * 28 / scale_divisor))
    export hvr=$((y_mon * 23 / scale_divisor))
    ;;
  2)
    wl_columns=2
    export x_mgn=$((x_mon * 35 / scale_divisor))
    export y_mgn=$((y_mon * 25 / scale_divisor))
    export x_hvr=$((x_mon * 32 / scale_divisor))
    export y_hvr=$((y_mon * 20 / scale_divisor))
    ;;
esac

#// scale font size

export fntSize=$((y_mon * 2 / 100))

#// detect wallpaper brightness

WALLPAPER_CURRENT_DIR="${WALLPAPER_CURRENT_DIR:-${HYPR_CACHE_HOME}/wallpaper/current}"
resolved_color_variant="${resolved_color_variant:-dark}"
BtnCol="${BtnCol:-}"
wal_cache="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
wal_background=""

if [ -r "${wal_cache}/colors.json" ]; then
  wal_background="$(jq -r '.special.background // empty' "${wal_cache}/colors.json")"
fi

if [ -z "${wal_background}" ] && [ -r "${wal_cache}/colors-shell.sh" ]; then
  # shellcheck disable=SC1090
  source "${wal_cache}/colors-shell.sh"
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
selected_color_mode="${selected_color_mode:-1}"
if [ -z "${BtnCol}" ]; then
  if [ "${selected_color_mode}" -eq 0 ]; then
    HYPR_THEME_DIR="${HYPR_THEME_DIR:-${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}}"
    resolved_color_variant=$(get_hypr_conf "COLOR_SCHEME")
    resolved_color_variant=${resolved_color_variant#prefer-}
  fi
  { [ "${resolved_color_variant}" == "dark" ] && BtnCol="white"; } || BtnCol="black"
fi
export BtnCol

#// eval hypr border radius

hypr_border="${HYPR_RUNTIME_BORDER_RADIUS:-${HYPR_BORDER_RADIUS:-10}}"
export active_rad=$((hypr_border * 5))
export button_rad=$((hypr_border * 8))

#// eval config files

wl_style="$(envsubst <"${wl_template}")"

#// launch wlogout

wlogout -b "${wl_columns}" -c 0 -r 0 -m 0 --layout "${wl_layout}" --css <(echo "${wl_style}") --protocol layer-shell
