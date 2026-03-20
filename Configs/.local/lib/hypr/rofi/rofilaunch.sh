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
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

resolve_rofi_launcher_theme() {
  local style_ref="${1:-${ROFI_LAUNCH_STYLE:-style_1}}"
  local normalized_style=""

  normalized_style="$(rofi_normalize_launcher_style "${style_ref}")"
  rofi_resolve_theme "${normalized_style}"
}

launcher_style_select() {
  local font_scale font_name font_override current_style
  local hypr_border elem_border icon_border
  local mon_x_res mon_y_res elm_width elm_height max_avail_x max_avail_y col_count row_count r_override
  local selected_style preview_asset
  local preview_image_size hidpi_scale
  local launcher_style_icon_size launcher_style_element_padding
  local launcher_style_list_spacing launcher_style_list_padding

  font_scale="$(rofi_effective_font_scale "${ROFI_SELECT_SCALE:-${ROFI_LAUNCH_SCALE:-}}")"
  font_name="$(rofi_effective_font_name "${ROFI_SELECT_FONT:-${ROFI_LAUNCH_FONT:-$ROFI_FONT}}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  current_style="$(rofi_normalize_launcher_style "${ROFI_LAUNCH_STYLE:-style_1}")"

  preview_image_size="${ROFI_LAUNCH_SELECT_PREVIEW_SIZE:-192}"
  hidpi_scale="${ROFI_LAUNCH_SELECT_HIDPI_SCALE:-2}"
  launcher_style_icon_size="${ROFI_LAUNCH_SELECT_ICON_SIZE:-20}"
  launcher_style_element_padding="${ROFI_LAUNCH_SELECT_ELEMENT_PADDING:-0em}"
  launcher_style_list_spacing="${ROFI_LAUNCH_SELECT_LIST_SPACING:-3em}"
  launcher_style_list_padding="${ROFI_LAUNCH_SELECT_LIST_PADDING:-1em}"

  [[ "${preview_image_size}" =~ ^[0-9]+$ ]] || preview_image_size=192
  [[ "${hidpi_scale}" =~ ^[0-9]+$ ]] || hidpi_scale=2
  [[ "${launcher_style_icon_size}" =~ ^[0-9]+$ ]] || launcher_style_icon_size=20

  hypr_border="$(rofi_default_border_radius 10)"
  elem_border=$((hypr_border * 5))
  icon_border=$((elem_border - 5))
  [[ "${icon_border}" -lt 0 ]] && icon_border=0

  read -r mon_x_res mon_y_res < <(rofi_focused_monitor_logical_size)
  mon_x_res=${mon_x_res:-1920}
  mon_y_res=${mon_y_res:-1080}
  elm_width=$((preview_image_size * hidpi_scale))
  elm_height=$((preview_image_size * hidpi_scale))
  max_avail_x=$((mon_x_res - (8 * font_scale)))
  max_avail_y=$((mon_y_res - (16 * font_scale)))
  col_count=$((max_avail_x / elm_width))
  row_count=$((max_avail_y / elm_height))
  [[ "${col_count}" -lt 2 ]] && col_count=2
  [[ "${col_count}" -gt 5 ]] && col_count=5
  [[ "${row_count}" -lt 2 ]] && row_count=2
  [[ "${row_count}" -gt 4 ]] && row_count=4

  r_override="window{width:100%;height:100%;fullscreen:true;}
      listview{columns:${col_count};lines:${row_count};cycle:true;spacing:${launcher_style_list_spacing};padding:${launcher_style_list_padding};}
      element{orientation:vertical;border-radius:${elem_border}px;padding:${launcher_style_element_padding};}
      element-icon{border-radius:${icon_border}px;size:${launcher_style_icon_size}em;}
      element-text{enabled:false;}"

  selected_style="$({
    rofi_list_theme_files | while IFS= read -r theme_file; do
      rg -q "Attribute: .*launcher" "${theme_file}" || continue
      style_name="$(basename "${theme_file}" .rasi)"
      preview_asset="$(rofi_theme_preview_asset "${style_name}" 2>/dev/null || true)"
      if [[ -n "${preview_asset}" ]] && [[ -f "${preview_asset}" ]]; then
        printf '%s\0icon\x1f%s\n' "${style_name}" "${preview_asset}"
      else
        printf '%s\n' "${style_name}"
      fi
    done
  } | sort -V | rofi -dmenu -i \
      -theme "$(rofi_resolve_theme "${ROFI_SELECT_STYLE:-theme_select}")" \
      -theme-str "${font_override}" \
      -theme-str "${r_override}" \
      -select "${current_style}" )"

  [[ -z "${selected_style}" ]] && return 0

  state_set "ROFI_LAUNCH_STYLE" "${selected_style}" "staterc"
  preview_asset="$(rofi_theme_preview_asset "${selected_style}" 2>/dev/null || true)"
  if command -v dunstify >/dev/null 2>&1; then
    local -a notify_args=(-a "Launcher style" -t 2200 -r 94)
    [[ -n "${preview_asset}" ]] && [[ -f "${preview_asset}" ]] && notify_args+=(-i "${preview_asset}")
    dunstify "${notify_args[@]}" "Launcher style applied" "${selected_style}"
  fi
}

rofi_config="$(resolve_rofi_launcher_theme)"

font_scale="$(rofi_effective_font_scale "${ROFI_LAUNCH_SCALE}")"

rofi_args=(
  -show-icons
)

#// rofi action

case "${1}" in
  d | --drun)
    r_mode="drun"
    rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_DRUN_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
    rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]:-}")
    rofi_args+=("-run-command" "app2unit.sh -- {cmd}")
    ;;
  w | --window)
    r_mode="window"
    rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_WINDOW_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
    rofi_args+=("${ROFI_LAUNCH_WINDOW_ARGS[@]:-}")
    ;;
  f | --filebrowser)
    r_mode="filebrowser"
    rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_FILEBROWSER_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
    rofi_args+=("${ROFI_LAUNCH_FILEBROWSER_ARGS[@]:-}")
    ;;
  r | --run)
    r_mode="run"
    rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_RUN_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
    rofi_args+=("-run-command" "app2unit.sh -- {cmd}")
    rofi_args+=("${ROFI_LAUNCH_RUN_ARGS[@]:-}")
    ;;
  s | -s | --select-style)
    launcher_style_select
    exit 0
    ;;
  h | --help)
    echo -e "$(basename "${0}") [action]"
    echo "d :  drun mode"
    echo "w :  window mode"
    echo "f :  filebrowser mode"
    echo "r :  run mode"
    echo "s :  select launcher style"
    exit 0
    ;;
  *)
    r_mode="drun"
    rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_DRUN_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
    rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]:-}")
    rofi_args+=("-run-command" "app2unit.sh -- {cmd}")
    ;;
esac

#// wallpaper sizing (match window width to wallpaper aspect ratio)
rofi_theme_file="${rofi_config}"

width_override=""
margin_px="${ROFI_LAUNCH_MARGIN_PX:-${ROFI_LAUNCH_MARGIN:-0}}"
[[ "${margin_px}" =~ ^[0-9]+$ ]] || margin_px=0
width_override="$(rofi_wallpaper_width_override "${rofi_theme_file}" "${font_scale}" "${margin_px}")"

width_override_args=()
if [[ -n "${width_override}" ]]; then
  width_override_args=(-theme-str "${width_override}")
fi

#// set overrides
base_border_radius="$(rofi_default_border_radius 10)"
hypr_border="${base_border_radius}"
hypr_width="$(rofi_default_border_width 2)"
elem_border="0"
[[ "${base_border_radius}" -ne 0 ]] && elem_border=$((base_border_radius * 2))

if [[ -f "${HYPR_STATE_HOME}/fullscreen_${r_mode}" ]]; then
  hypr_width="0"
  hypr_border="0"
fi

r_override="window {border: ${hypr_width}px; border-radius: ${hypr_border}px;} element {border-radius: ${elem_border}px;} button {border-radius: ${elem_border}px;}"

font_name="$(rofi_effective_font_name "${ROFI_LAUNCH_FONT:-$ROFI_FONT}")"
font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
i_override="$(rofi_icon_theme_override)"

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

# Cache fullscreen state after resolving the active launcher theme.

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
