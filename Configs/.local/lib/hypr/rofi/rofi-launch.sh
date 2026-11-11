#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_load_shell_environment || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/close.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"

LAUNCHER_STYLE_NOTIFY_MS=2200
LAUNCHER_STYLE_ICON_EM=20
LAUNCHER_STYLE_FALLBACK_RADIUS_PX=10
LAUNCHER_STYLE_RADIUS_SCALE=5

resolve_rofi_launcher_theme() {
  local style_ref="${1:-${ROFI_LAUNCH_STYLE:-sidebar}}"
  rofi_resolve_theme "$(rofi_normalize_launcher_style "${style_ref}")"
}

launcher_run_command() {
  printf '%s\n' "${HYPR_LIB_DIR}/rofi/run-after-close.sh -- hyprshell app -- {cmd}"
}

show_help() {
  echo "${0##*/} [action]"
  echo "d : drun mode"
  echo "w : window mode"
  echo "f : filebrowser mode"
  echo "r : run mode"
  echo "s : select launcher style"
  exit 0
}

launcher_style_notification() {
  local selected_style="$1"
  local preview_asset="$2"

  command -v dunstify >/dev/null 2>&1 || return 0

  local -a notify_args=(-a "Launcher style" -t "${LAUNCHER_STYLE_NOTIFY_MS}" -r "${NOTIFY_ID_LAUNCHER_STYLE}")
  [[ -n "${preview_asset}" && -f "${preview_asset}" ]] && notify_args+=(-i "${preview_asset}")
  dunstify "${notify_args[@]}" "Launcher style applied" "${selected_style}"
}

launcher_style_menu_override() {
  local launcher_style_icon_size="${ROFI_LAUNCH_SELECT_ICON_SIZE:-${LAUNCHER_STYLE_ICON_EM}}"
  local hypr_border=""
  local elem_border=0
  local icon_border=0
  local mon_x_res_px=0
  local mon_y_res_px=0
  local col_count=3

  [[ "${launcher_style_icon_size}" =~ ^[0-9]+$ ]] || launcher_style_icon_size="${LAUNCHER_STYLE_ICON_EM}"

  hypr_border="$(rofi_default_border_radius "${LAUNCHER_STYLE_FALLBACK_RADIUS_PX}")"
  elem_border=$((hypr_border * LAUNCHER_STYLE_RADIUS_SCALE))
  icon_border=$((elem_border - LAUNCHER_STYLE_RADIUS_SCALE))
  [[ "${icon_border}" -lt 0 ]] && icon_border=0

  read -r mon_x_res_px mon_y_res_px < <(rofi_focused_monitor_logical_size)
  local icon_size="(${launcher_style_icon_size}em min $((mon_x_res_px / col_count))px min ${mon_y_res_px}px)"

  cat <<EOF
window{width:100%;height:100%;fullscreen:true;}
mainbox{children:[frame];spacing:0px;}
frame{spacing:0px;}
inputbar{enabled:false;}
listview{columns:${col_count};lines:1;cycle:true;fixed-columns:true;fixed-height:true;spacing:0px;padding:0px;scrollbar:false;}
element{orientation:vertical;border-radius:0px;padding:calc((${mon_y_res_px}px - ${icon_size}) / 2) 0px;}
element-icon{border-radius:${icon_border}px;size:calc(${icon_size});}
element-text{enabled:false;}
EOF
}

list_launcher_styles() {
  local theme_file=""
  local style_name=""
  local preview_asset=""

  rofi_list_theme_files | while IFS= read -r theme_file; do
    rg -q "Attribute: .*launcher" "${theme_file}" || continue
    style_name="${theme_file##*/}"
    style_name="${style_name%.rasi}"
    preview_asset="$(rofi_theme_preview_asset "${style_name}" 2>/dev/null || true)"
    if [[ -n "${preview_asset}" && -f "${preview_asset}" ]]; then
      printf '%s\0icon\x1f%s\n' "${style_name}" "${preview_asset}"
    else
      printf '%s\n' "${style_name}"
    fi
  done | sort -V
}

launcher_style_select_and_save() {
  local font_scale=""
  local font_name=""
  local font_override=""
  local current_style=""
  local menu_window_override=""
  local selected_style=""
  local preview_asset=""

  font_scale="$(rofi_effective_font_scale "${ROFI_SELECT_SCALE:-${ROFI_LAUNCH_SCALE:-}}")"
  font_name="$(rofi_effective_font_name "${ROFI_SELECT_FONT:-${ROFI_LAUNCH_FONT:-$ROFI_FONT}}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  current_style="$(rofi_normalize_launcher_style "${ROFI_LAUNCH_STYLE:-sidebar}")"
  menu_window_override="$(launcher_style_menu_override)"

  selected_style="$(
    list_launcher_styles | rofi_with_background_theme -dmenu -i \
      "${ROFI_MOUSE_SELECT_ARGS[@]}" \
      -theme "$(rofi_resolve_theme "${ROFI_SELECT_STYLE:-theme_select}")" \
      -theme-str "${font_override}" \
      -theme-str "${menu_window_override}" \
      -select "${current_style}"
  )"

  [[ -n "${selected_style}" ]] || return 0
  state_set "ROFI_LAUNCH_STYLE" "${selected_style}" "staterc"
  preview_asset="$(rofi_theme_preview_asset "${selected_style}" 2>/dev/null || true)"
  launcher_style_notification "${selected_style}" "${preview_asset}"
}

configure_drun_mode() {
  rofi_mode="drun"
  rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_DRUN_STYLE:-${ROFI_LAUNCH_STYLE:-sidebar}}")"
  rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]}" "-run-command" "$(launcher_run_command)")
}

configure_mode() {
  local action="${1:-}"
  rofi_args=(-show-icons -me-select-entry "" -me-accept-entry MousePrimary)

  case "${action}" in
    d | --drun | "") configure_drun_mode ;;
    w | --window)
      rofi_mode="window"
      rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_WINDOW_STYLE:-${ROFI_LAUNCH_STYLE:-sidebar}}")"
      rofi_args+=("${ROFI_LAUNCH_WINDOW_ARGS[@]}")
      ;;
    f | --filebrowser)
      rofi_mode="filebrowser"
      rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_FILEBROWSER_STYLE:-${ROFI_LAUNCH_STYLE:-sidebar}}")"
      rofi_args+=("${ROFI_LAUNCH_FILEBROWSER_ARGS[@]}")
      ;;
    r | --run)
      rofi_mode="run"
      rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_RUN_STYLE:-${ROFI_LAUNCH_STYLE:-sidebar}}")"
      rofi_args+=("-run-command" "$(launcher_run_command)" "${ROFI_LAUNCH_RUN_ARGS[@]}")
      ;;
    s | -s | --select-style)
      rofi_ensure_closed || exit 1
      launcher_style_select_and_save
      exit 0
      ;;
    h | --help)
      show_help
      ;;
    *) configure_drun_mode ;;
  esac
}

append_runtime_overrides_into() {
  local -n launch_args_ref="$1"
  local font_scale="$2"
  local font_name="$3"
  local font_override=""
  local icon_override=""
  local window_override=""
  local width_override=""

  window_override="$(rofi_window_override "${rofi_config}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  icon_override="$(rofi_icon_theme_override)"

  launch_args_ref+=(-theme-str "${font_override}" -theme-str "${icon_override}" -theme-str "${window_override}")

  if ! rofi_theme_is_fullscreen "${rofi_config}"; then
    width_override="$(rofi_wallpaper_width_override "${rofi_config}" "${font_name}" "${font_scale}")"
    launch_args_ref+=(-theme-str "${width_override:-$(rofi_window_position_theme)}")
  fi

  launch_args_ref+=(-theme "${rofi_config}")
}

launch_rofi() {
  local font_scale=""
  local font_name=""

  rofi_hypr_snapshot
  font_scale="$(rofi_effective_font_scale "${ROFI_LAUNCH_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_LAUNCH_FONT:-$ROFI_FONT}")"
  append_runtime_overrides_into rofi_args "${font_scale}" "${font_name}"
  rofi_with_background_theme -show "${rofi_mode}" "${rofi_args[@]}" &
  disown
}

configure_mode "${1:-}"
rofi_ensure_closed || exit 1
launch_rofi
