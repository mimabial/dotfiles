#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_help_guard "Usage: hyprshell session/logout-launch [style]
Open the wlogout menu (toggles off if already running)." "$@"

hypr_runtime_require state system || exit 1
hypr_runtime_load_state || exit 1

if hypr_user_pgrep -x "wlogout" >/dev/null; then
  hypr_user_pkill -x "wlogout"
  exit 0
fi

[ -n "${1:-}" ] && wlogout_style="${1}"
wlogout_style=${wlogout_style:-${WLOGOUT_STYLE:-}}
wlogout_layout="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout/layout_${wlogout_style}"
wlogout_style_template="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout/style_${wlogout_style}.css"
echo "wlogout_style: ${wlogout_style}"
echo "wlogout_layout: ${wlogout_layout}"
echo "wlogout_style_template: ${wlogout_style_template}"

if [ ! -f "${wlogout_layout}" ] || [ ! -f "${wlogout_style_template}" ]; then
  echo "ERROR: Config ${wlogout_style} not found..."
  wlogout_style=1
  wlogout_layout="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout/layout_${wlogout_style}"
  wlogout_style_template="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout/style_${wlogout_style}.css"
fi

# Treat scale as fixed-point tenths so multi-decimal values like 1.25
# stay in the same sizing range as the existing 1.0/1.5/2.0 behavior.
read -r monitor_width monitor_height hypr_scale_tenths < <(
  hyprctl -j monitors \
    | jq -r 'first(.[] | select(.focused == true) | "\(.width) \(.height) \((.scale * 10 | round))") // empty'
)
monitor_width="${monitor_width:-1920}"
monitor_height="${monitor_height:-1080}"
hypr_scale_tenths="${hypr_scale_tenths:-10}"
[[ "${hypr_scale_tenths}" =~ ^[0-9]+$ ]] || hypr_scale_tenths=10
(( hypr_scale_tenths > 0 )) || hypr_scale_tenths=10
logical_pct_divisor=$((hypr_scale_tenths * 10))

case "${wlogout_style}" in
  1)
    wl_columns=6
    export mgn=$((monitor_height * 28 / logical_pct_divisor))
    export hvr=$((monitor_height * 23 / logical_pct_divisor))
    ;;
  2)
    wl_columns=2
    export x_mgn=$((monitor_width * 35 / logical_pct_divisor))
    export y_mgn=$((monitor_height * 25 / logical_pct_divisor))
    export x_hvr=$((monitor_width * 32 / logical_pct_divisor))
    export y_hvr=$((monitor_height * 20 / logical_pct_divisor))
    ;;
esac

export fntSize=$((monitor_height * 2 / logical_pct_divisor))

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

BT601_R=299 BT601_G=587 BT601_B=114 BT601_SCALE=1000

if [ -n "${wal_background}" ]; then
  hex="${wal_background#\#}"
  if [[ "${#hex}" -ge 6 ]]; then
    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))
    luma=$(((r * BT601_R + g * BT601_G + b * BT601_B) / BT601_SCALE))
    if [ "${luma}" -lt 128 ]; then
      BtnCol="white"
    else
      BtnCol="black"
    fi
  fi
fi

if [ -z "${BtnCol}" ]; then
  if [[ "${selected_color_source:-theme}" == "theme" ]]; then
    HYPR_THEME_DIR="${HYPR_THEME_DIR:-${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}}"
    resolved_color_variant=$(get_hypr_conf "COLOR_SCHEME")
    resolved_color_variant=${resolved_color_variant#prefer-}
  fi
  { [ "${resolved_color_variant}" == "dark" ] && BtnCol="white"; } || BtnCol="black"
fi
export BtnCol

hypr_border="${HYPR_RUNTIME_BORDER_RADIUS:-${HYPR_BORDER_RADIUS:-10}}"
export active_rad=$((hypr_border * 5))
export button_rad=$((hypr_border * 8))

wlogout_css="$(envsubst <"${wlogout_style_template}")"

wlogout -b "${wl_columns}" -c 0 -r 0 -m 0 --layout "${wlogout_layout}" --css <(echo "${wlogout_css}") --protocol layer-shell
