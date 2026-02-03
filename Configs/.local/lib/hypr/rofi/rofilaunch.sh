#!/usr/bin/env bash

#// set variables

# Toggle: if rofi is running for current user, kill it and exit
if pgrep -u "$USER" rofi >/dev/null 2>&1; then
  pkill -u "$USER" rofi
  exit 0
fi

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

# rofiStyle is loaded from staterc via export_hypr_config
[[ -z "${rofiStyle}" ]] && rofiStyle="$(get_hyprConf "rofiStyle")"
[[ -z "${rofiStyle}" ]] && rofiStyle="1"
if [[ "${rofiStyle}" =~ ^[0-9]+$ ]]; then
  rofi_config="style_${rofiStyle:-1}"
else
  rofi_config="${rofiStyle:-"style_1"}"
fi

rofi_config="${ROFI_LAUNCH_STYLE:-$rofi_config}"

font_scale="${ROFI_LAUNCH_SCALE}"
[[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

rofi_args=(
  -show-icons
)

#// rofi action

case "${1}" in
  d | --drun)
    r_mode="drun"
    rofi_config="${ROFI_LAUNCH_DRUN_STYLE:-$rofi_config}"
    rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]:-}")
    rofi_args+=("-run-command" "app2unit.sh  --fuzzel-compat -- {cmd}")
    ;;
  w | --window)
    r_mode="window"
    rofi_config="${ROFI_LAUNCH_WINDOW_STYLE:-$rofi_config}"
    rofi_args+=("${ROFI_LAUNCH_WINDOW_ARGS[@]:-}")
    ;;
  f | --filebrowser)
    r_mode="filebrowser"
    rofi_config="${ROFI_LAUNCH_FILEBROWSER_STYLE:-$rofi_config}"
    rofi_args+=("${ROFI_LAUNCH_FILEBROWSER_ARGS[@]:-}")
    ;;
  r | --run)
    r_mode="run"
    rofi_config="${ROFI_LAUNCH_RUN_STYLE:-$rofi_config}"
    rofi_args+=("-run-command" "app2unit.sh  --fuzzel-compat -- {cmd}")
    rofi_args+=("${ROFI_LAUNCH_RUN_ARGS[@]:-}")
    ;;
  h | --help)
    echo -e "$(basename "${0}") [action]"
    echo "d :  drun mode"
    echo "w :  window mode"
    echo "f :  filebrowser mode,"
    echo "r :  run mode"
    exit 0
    ;;
  *)
    r_mode="drun"
    ROFI_LAUNCH_DRUN_STYLE="${ROFI_LAUNCH_DRUN_STYLE:-$ROFI_LAUNCH_STYLE}"
    rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]:-}")
    rofi_args+=("-run-command" "app2unit.sh  --fuzzel-compat -- {cmd}")
    rofi_config="${ROFI_LAUNCH_DRUN_STYLE:-$rofi_config}"
    ;;
esac

#// wallpaper sizing (match window width to wallpaper aspect ratio)
rofi_theme_file=""
if [[ -f "${rofi_config}" ]]; then
  rofi_theme_file="${rofi_config}"
elif [[ -f "${HOME}/.config/rofi/themes/${rofi_config}.rasi" ]]; then
  rofi_theme_file="${HOME}/.config/rofi/themes/${rofi_config}.rasi"
elif [[ -f "${HOME}/.config/rofi/themes/${rofi_config}" ]]; then
  rofi_theme_file="${HOME}/.config/rofi/themes/${rofi_config}"
elif [[ -f "${HOME}/.config/rofi/${rofi_config}.rasi" ]]; then
  rofi_theme_file="${HOME}/.config/rofi/${rofi_config}.rasi"
elif [[ -f "${HOME}/.config/rofi/${rofi_config}" ]]; then
  rofi_theme_file="${HOME}/.config/rofi/${rofi_config}"
fi

width_override=""
margin_px="${ROFI_LAUNCH_MARGIN_PX:-${ROFI_LAUNCH_MARGIN:-0}}"
[[ "${margin_px}" =~ ^[0-9]+$ ]] || margin_px=0
mon_data="$(hyprctl -j monitors 2>/dev/null || true)"
mon_width="$(jq -r '.[] | select(.focused==true) | .width' <<<"${mon_data}" 2>/dev/null | head -1)"
mon_scale="$(jq -r '.[] | select(.focused==true) | .scale' <<<"${mon_data}" 2>/dev/null | head -1)"
mon_width_logical=""
if [[ "${mon_width}" =~ ^[0-9]+$ ]]; then
  if [[ "${mon_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN { exit !(${mon_scale} > 0) }"; then
    mon_width_logical="$(awk -v w="${mon_width}" -v sc="${mon_scale}" 'BEGIN { printf "%.2f", (w / sc) }')"
  else
    mon_width_logical="${mon_width}"
  fi
fi
wall_cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current"
wall_image="${wall_cache_root}/wall.thmb"

if [[ -f "${wall_image}" ]] && [[ -n "${rofi_theme_file}" ]] && command -v magick >/dev/null 2>&1; then
  read -r theme_height theme_height_unit < <(
    awk '
      /^[[:space:]]*window[[:space:]]*\{/ {in_window=1; next}
      in_window && /^[[:space:]]*}/ {exit}
      in_window && /^[[:space:]]*height[[:space:]]*:/ {
        if (match($0, /:[[:space:]]*([0-9]+([.][0-9]+)?)([a-z%]*)/, m)) {
          print m[1], m[3]
        }
        exit
      }
    ' "${rofi_theme_file}"
  )

  if [[ "${theme_height_unit}" == "em" || "${theme_height_unit}" == "px" ]]; then
    read -r img_w img_h < <(magick identify -format "%w %h" "${wall_image}" 2>/dev/null || true)
    if [[ "${img_w}" =~ ^[0-9]+$ && "${img_h}" =~ ^[0-9]+$ && "${img_h}" -gt 0 ]]; then
      ratio="$(awk -v w="${img_w}" -v h="${img_h}" 'BEGIN { if (h <= 0) { print 0 } else { printf "%.6f", (w / h) } }')"
      if [[ "${theme_height_unit}" == "px" ]]; then
        width_value="$(awk -v h="${theme_height}" -v r="${ratio}" 'BEGIN { printf "%.2f", (h * r) }')"
        if [[ -n "${mon_width_logical}" ]] && awk -v w="${mon_width_logical}" -v m="${margin_px}" 'BEGIN { exit !(w > (m * 2)) }'; then
          max_width_px="$(awk -v w="${mon_width_logical}" -v m="${margin_px}" 'BEGIN { val = w - (m * 2); if (val < 0) val = 0; printf "%.2f", val }')"
          width_value="$(awk -v w="${width_value}" -v max="${max_width_px}" 'BEGIN { if (w > max) w = max; printf "%.2f", w }')"
        fi
        width_override="window { width: ${width_value}px; }"
      else
        width_value="$(awk -v h="${theme_height}" -v r="${ratio}" 'BEGIN { printf "%.2f", (h * r) }')"
        if [[ -n "${mon_width_logical}" && "${font_scale}" =~ ^[0-9]+$ && "${font_scale}" -gt 0 ]]; then
          font_px="$(awk -v fs="${font_scale}" 'BEGIN { printf "%.3f", (fs * 96 / 72) }')"
          max_width_em="$(awk -v w="${mon_width_logical}" -v m="${margin_px}" -v fp="${font_px}" 'BEGIN { val = (w - (m * 2)) / fp; if (val < 0) val = 0; printf "%.2f", val }')"
          width_value="$(awk -v w="${width_value}" -v max="${max_width_em}" 'BEGIN { if (w > max) w = max; printf "%.2f", w }')"
        fi
        width_override="window { width: ${width_value}em; }"
      fi
    fi
  fi
fi

width_override_args=()
if [[ -n "${width_override}" ]]; then
  width_override_args=(-theme-str "${width_override}")
fi

#// set overrides
hypr_border="${hypr_border:-10}"
hypr_width="${hypr_width:-2}"
wind_border=$((hypr_border * 3))

if [[ -f "${HYPR_STATE_HOME}/fullscreen_${r_mode}" ]]; then
  hypr_width="0"
  wind_border="0"
fi

[ "${hypr_border}" -eq 0 ] && elem_border="0" || elem_border=$((hypr_border * 2))

[[ -z "${mon_data}" ]] && mon_data=$(hyprctl -j monitors 2>/dev/null || true)
is_vertical=$(jq -r '.[] | select(.focused==true) | (if (.transform % 2 == 0) then (.width < .height) else (.height < .width) end)' <<<"${mon_data}" 2>/dev/null || true)
[[ "${is_vertical}" != "true" ]] && is_vertical="false"

r_override="window {border: ${hypr_width}px; border-radius: ${hypr_border}px;} element {border-radius: ${elem_border}px;} button {border-radius: ${elem_border}px;}"

# set font name
font_name=${ROFI_LAUNCH_FONT:-$ROFI_FONT}
font_name=${font_name:-$(hyprshell font-get menu 2>/dev/null || true)}
font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
font_name=${font_name:-$(get_hyprConf "FONT")}
font_name=${font_name:-monospace}

# set rofi font override
font_override="* {font: \"${font_name} ${font_scale}\";}"

i_override="$(get_hyprConf "ICON_THEME")"
i_override="configuration {icon-theme: \"${i_override}\";}"

rofi_args+=(
  -theme-str "${font_override}"
  -theme-str "${i_override}"
  -theme-str "${r_override}"
  "${width_override_args[@]}"
  -theme "${rofi_config}"
)

#// launch rofi
rofi -show "${r_mode}" "${rofi_args[@]}" &
disown
echo -show "${r_mode}" "${rofi_args[@]}"

#// Set full screen state
#TODO Contributor notes:
#? - Workaround to set the full screen state of rofi dynamically and efficiently.
#? - Avoids invoking rofi twice before rendering.
#? - Checks if the theme has fullscreen set to true after rendering.
#? - Sets the variable accordingly for use on the next launch.

rofi -show "${r_mode}" \
  -show-icons \
  -config "${rofi_config}" \
  -theme-str "${font_override}" \
  -theme-str "${i_override}" \
  -theme-str "${r_override}" \
  -theme "${rofi_config}" \
  "${width_override_args[@]}" \
  -dump-theme \
  | { grep -q "fullscreen.*true" && touch "${HYPR_STATE_HOME}/fullscreen_${r_mode}"; } || rm -f "${HYPR_STATE_HOME}/fullscreen_${r_mode}"
