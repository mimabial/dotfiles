#!/usr/bin/env bash

toggle_running_rofi() {
  pkill -u "$USER" -x rofi >/dev/null 2>&1 && exit 0
}

ensure_rofi_runtime() {
  local lib_root="${LIB_DIR:-}"
  local hyprshell_path=""

  if [[ -z "${lib_root}" ]]; then
    hyprshell_path="$(command -v hyprshell)" || return 1
    lib_root="$(realpath "$(dirname "${hyprshell_path}")/../lib")" || return 1
    export LIB_DIR="${lib_root}"
  fi

  # shellcheck source=/dev/null
  source "${lib_root}/hypr/globalcontrol.sh" || return 1
}

toggle_running_rofi

ensure_rofi_runtime || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

resolve_rofi_launcher_theme() {
  local style_ref="${1:-${ROFI_LAUNCH_STYLE:-style_1}}"
  rofi_resolve_theme "$(rofi_normalize_launcher_style "${style_ref}")"
}

show_help() {
  echo "$(basename "${0}") [action]"
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

  local -a notify_args=(-a "Launcher style" -t 2200 -r 94)
  [[ -n "${preview_asset}" && -f "${preview_asset}" ]] && notify_args+=(-i "${preview_asset}")
  dunstify "${notify_args[@]}" "Launcher style applied" "${selected_style}"
}

launcher_style_menu_override() {
  local font_scale="$1"
  local preview_image_size="${ROFI_LAUNCH_SELECT_PREVIEW_SIZE:-192}"
  local hidpi_scale="${ROFI_LAUNCH_SELECT_HIDPI_SCALE:-2}"
  local launcher_style_icon_size="${ROFI_LAUNCH_SELECT_ICON_SIZE:-20}"
  local launcher_style_element_padding="${ROFI_LAUNCH_SELECT_ELEMENT_PADDING:-0em}"
  local launcher_style_list_spacing="${ROFI_LAUNCH_SELECT_LIST_SPACING:-3em}"
  local launcher_style_list_padding="${ROFI_LAUNCH_SELECT_LIST_PADDING:-1em}"
  local hypr_border=""
  local elem_border=0
  local icon_border=0
  local mon_x_res=1920
  local mon_y_res=1080
  local elm_width=0
  local elm_height=0
  local max_avail_x=0
  local max_avail_y=0
  local col_count=0
  local row_count=0

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

  cat <<EOF
window{width:100%;height:100%;fullscreen:true;}
listview{columns:${col_count};lines:${row_count};cycle:true;spacing:${launcher_style_list_spacing};padding:${launcher_style_list_padding};}
element{orientation:vertical;border-radius:${elem_border}px;padding:${launcher_style_element_padding};}
element-icon{border-radius:${icon_border}px;size:${launcher_style_icon_size}em;}
element-text{enabled:false;}
EOF
}

list_launcher_styles() {
  local theme_file=""
  local style_name=""
  local preview_asset=""

  rofi_list_theme_files | while IFS= read -r theme_file; do
    rg -q "Attribute: .*launcher" "${theme_file}" || continue
    style_name="$(basename "${theme_file}" .rasi)"
    preview_asset="$(rofi_theme_preview_asset "${style_name}" 2>/dev/null || true)"
    if [[ -n "${preview_asset}" && -f "${preview_asset}" ]]; then
      printf '%s\0icon\x1f%s\n' "${style_name}" "${preview_asset}"
    else
      printf '%s\n' "${style_name}"
    fi
  done | sort -V
}

launcher_style_select() {
  local font_scale=""
  local font_name=""
  local font_override=""
  local current_style=""
  local r_override=""
  local selected_style=""
  local preview_asset=""

  font_scale="$(rofi_effective_font_scale "${ROFI_SELECT_SCALE:-${ROFI_LAUNCH_SCALE:-}}")"
  font_name="$(rofi_effective_font_name "${ROFI_SELECT_FONT:-${ROFI_LAUNCH_FONT:-$ROFI_FONT}}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  current_style="$(rofi_normalize_launcher_style "${ROFI_LAUNCH_STYLE:-style_1}")"
  r_override="$(launcher_style_menu_override "${font_scale}")"

  selected_style="$(
    list_launcher_styles | rofi -dmenu -i \
      -theme "$(rofi_resolve_theme "${ROFI_SELECT_STYLE:-theme_select}")" \
      -theme-str "${font_override}" \
      -theme-str "${r_override}" \
      -select "${current_style}"
  )"

  [[ -n "${selected_style}" ]] || return 0
  state_set "ROFI_LAUNCH_STYLE" "${selected_style}" "staterc"
  preview_asset="$(rofi_theme_preview_asset "${selected_style}" 2>/dev/null || true)"
  launcher_style_notification "${selected_style}" "${preview_asset}"
}

configure_mode() {
  local action="${1:-}"
  rofi_args=(-show-icons)

  case "${action}" in
    d|--drun|"")
      r_mode="drun"
      rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_DRUN_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
      rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]:-}" "-run-command" "app2unit.sh -- {cmd}")
      ;;
    w|--window)
      r_mode="window"
      rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_WINDOW_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
      rofi_args+=("${ROFI_LAUNCH_WINDOW_ARGS[@]:-}")
      ;;
    f|--filebrowser)
      r_mode="filebrowser"
      rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_FILEBROWSER_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
      rofi_args+=("${ROFI_LAUNCH_FILEBROWSER_ARGS[@]:-}")
      ;;
    r|--run)
      r_mode="run"
      rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_RUN_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
      rofi_args+=("-run-command" "app2unit.sh -- {cmd}" "${ROFI_LAUNCH_RUN_ARGS[@]:-}")
      ;;
    s|-s|--select-style)
      launcher_style_select
      exit 0
      ;;
    h|--help)
      show_help
      ;;
    *)
      r_mode="drun"
      rofi_config="$(resolve_rofi_launcher_theme "${ROFI_LAUNCH_DRUN_STYLE:-${ROFI_LAUNCH_STYLE:-style_1}}")"
      rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]:-}" "-run-command" "app2unit.sh -- {cmd}")
      ;;
  esac
}

width_override_args() {
  local rofi_theme_file="$1"
  local font_name="$2"
  local font_scale="$3"
  local margin_px="${ROFI_LAUNCH_MARGIN_PX:-${ROFI_LAUNCH_MARGIN:-0}}"
  local width_override=""

  [[ "${margin_px}" =~ ^[0-9]+$ ]] || margin_px=0
  width_override="$(rofi_wallpaper_width_override "${rofi_theme_file}" "${font_name}" "${font_scale}" "${margin_px}")"
  [[ -n "${width_override}" ]] && printf '%s\0%s\n' "-theme-str" "${width_override}"
}

build_runtime_overrides() {
  local font_scale="$1"
  local font_name="$2"
  local base_border_radius=""
  local hypr_border=""
  local hypr_width=""
  local elem_border=0
  local font_override=""
  local icon_override=""
  local window_override=""

  base_border_radius="$(rofi_default_border_radius 10)"
  hypr_border="${base_border_radius}"
  hypr_width="$(rofi_default_border_width 2)"
  [[ "${base_border_radius}" -ne 0 ]] && elem_border=$((base_border_radius * 2))

  if rofi_theme_is_fullscreen "${rofi_config}"; then
    hypr_width="0"
    hypr_border="0"
  fi

  window_override="window {border: ${hypr_width}px; border-radius: ${hypr_border}px;} inputbar {border-radius: ${hypr_border}px;} listbox {border-radius: ${hypr_border}px;} element {border-radius: ${elem_border}px;} button {border-radius: ${elem_border}px;}"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  icon_override="$(rofi_icon_theme_override)"

  rofi_args+=(-theme-str "${font_override}" -theme-str "${icon_override}" -theme-str "${window_override}")

  mapfile -d '' -t width_args < <(width_override_args "${rofi_config}" "${font_name}" "${font_scale}" | tr '\n' '\0')
  [[ ${#width_args[@]} -gt 0 ]] && rofi_args+=("${width_args[@]}")
  rofi_args+=(-theme "${rofi_config}")
}

launch_rofi() {
  local font_scale=""
  local font_name=""

  font_scale="$(rofi_effective_font_scale "${ROFI_LAUNCH_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_LAUNCH_FONT:-$ROFI_FONT}")"
  build_runtime_overrides "${font_scale}" "${font_name}"
  rofi -show "${r_mode}" "${rofi_args[@]}" &
  disown
}

configure_mode "${1:-}"
launch_rofi
