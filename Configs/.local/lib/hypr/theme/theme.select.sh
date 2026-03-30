#!/usr/bin/env bash

source "$(command -v hyprshell)" || exit 1
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/rofi/rofi.lib.bash"

theme_select_notify() {
  local icon_path="$1"
  shift

  local -a args=(-a "Theme select" -t 2000 -r 92)
  [[ -n "${icon_path}" ]] && args+=(-i "${icon_path}")
  notify_send_safe "${args[@]}" "$@" || true
}

help_message() {
  cat <<HELP
Usage: $(basename "${0}") --select-menu|-s [style]

menu style:
  --select-menu|-s   Select a menu style for this program

selector style:
  quad|2             quad style
  square|1           square style
HELP
  exit 0
}

theme_selector_monitor_metrics() {
  local hypr_border=2
  local mon_x_res=1920
  local mon_y_res=1080

  hypr_border="$(rofi_default_border_radius 2)"
  read -r mon_x_res mon_y_res < <(rofi_focused_monitor_logical_size)
  mon_x_res=${mon_x_res:-1920}
  mon_y_res=${mon_y_res:-1080}

  printf '%s\t%s\t%s\n' "${hypr_border}" "${mon_x_res}" "${mon_y_res}"
}

theme_selector_grid_counts() {
  local font_scale="$1"
  local elm_width="$2"
  local elm_height="$3"
  local horizontal_padding="$4"
  local vertical_padding="$5"
  local min_columns="${6:-}"
  local max_columns="${7:-}"
  local min_rows="${8:-}"
  local max_rows="${9:-}"
  local mon_x_res=1920
  local mon_y_res=1080
  local max_avail_x=0
  local max_avail_y=0
  local col_count=0
  local row_count=0

  read -r _ mon_x_res mon_y_res < <(theme_selector_monitor_metrics)
  max_avail_x=$((mon_x_res - (horizontal_padding * font_scale)))
  max_avail_y=$((mon_y_res - (vertical_padding * font_scale)))
  col_count=$((max_avail_x / elm_width))
  row_count=$((max_avail_y / elm_height))

  if [[ -n "${min_columns}" ]] && ((col_count < min_columns)); then
    col_count="${min_columns}"
  fi

  if [[ -n "${max_columns}" ]] && ((col_count > max_columns)); then
    col_count="${max_columns}"
  fi

  if [[ -n "${min_rows}" ]] && ((row_count < min_rows)); then
    row_count="${min_rows}"
  fi

  if [[ -n "${max_rows}" ]] && ((row_count > max_rows)); then
    row_count="${max_rows}"
  fi

  printf '%s\t%s\n' "${col_count}" "${row_count}"
}

build_style_menu_override() {
  local font_scale="$1"
  local preview_image_size="${ROFI_THEME_MENU_PREVIEW_SIZE:-192}"
  local hidpi_scale="${ROFI_THEME_MENU_HIDPI_SCALE:-2}"
  local theme_menu_icon_size="${ROFI_THEME_MENU_ICON_SIZE:-20}"
  local theme_menu_element_padding="${ROFI_THEME_MENU_ELEMENT_PADDING:-0em}"
  local theme_menu_list_spacing="${ROFI_THEME_MENU_LIST_SPACING:-3em}"
  local theme_menu_list_padding="${ROFI_THEME_MENU_LIST_PADDING:-1em}"
  local max_columns=5
  local min_rows=2
  local max_rows=4
  local hypr_border=2
  local horizontal_padding=8
  local vertical_padding=16
  local border_multiplier=5
  local elem_border=0
  local icon_border=0
  local elm_width=0
  local elm_height=0
  local col_count=0
  local row_count=0

  [[ "${preview_image_size}" =~ ^[0-9]+$ ]] || preview_image_size=192
  [[ "${hidpi_scale}" =~ ^[0-9]+$ ]] || hidpi_scale=2
  [[ "${theme_menu_icon_size}" =~ ^[0-9]+$ ]] || theme_menu_icon_size=20
  read -r hypr_border _ _ < <(theme_selector_monitor_metrics)

  elem_border=$((hypr_border * border_multiplier))
  icon_border=$((elem_border - 5))
  elm_width=$((preview_image_size * hidpi_scale))
  elm_height=$((preview_image_size * hidpi_scale))
  read -r col_count row_count < <(
    theme_selector_grid_counts \
      "${font_scale}" \
      "${elm_width}" \
      "${elm_height}" \
      "${horizontal_padding}" \
      "${vertical_padding}" \
      "" \
      "${max_columns}" \
      "${min_rows}" \
      "${max_rows}"
  )

  cat <<EOF
window{width:100%;height:100%;fullscreen:true;}
listview{columns:${col_count};lines:${row_count};cycle:true;spacing:${theme_menu_list_spacing};padding:${theme_menu_list_padding};}
element{orientation:vertical;border-radius:${elem_border}px;padding:${theme_menu_element_padding};}
element-icon{border-radius:${icon_border}px;size:${theme_menu_icon_size}em;}
element-text{enabled:false;}
EOF
}

list_style_menu_entries() {
  rofi_list_asset_files 'theme_style_*' \
    | awk -F '[_.]' '{print $((NF - 1))}' \
    | while read -r style_num; do
      printf '%s\x00icon\x1f%s\n' "${style_num}" "$(rofi_resolve_asset "theme_style_${style_num}.png")"
    done | sort -n
}

show_style_selector() {
  local font_scale=""
  local font_name=""
  local font_override=""
  local layout_override=""
  local selection=""
  local style_icon=""

  font_scale="$(rofi_effective_font_scale "${ROFI_THEME_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_THEME_MENU_FONT:-$ROFI_FONT}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  layout_override="$(build_style_menu_override "${font_scale}")"

  selection="$(
    list_style_menu_entries | rofi -dmenu -i \
      -theme "$(rofi_resolve_theme "${ROFI_THEME_MENU_STYLE:-theme_select}")" \
      -theme-str "${font_override}" \
      -theme-str "${layout_override}" \
      -select "${ROFI_THEME_STYLE}"
  )"

  [[ -n "${selection}" ]] || exit 0

  state_set "ROFI_THEME_STYLE" "${selection}" "staterc"
  style_icon="$(rofi_resolve_asset "theme_style_${selection}.png")"
  [[ -f "${style_icon}" ]] || style_icon="preferences-desktop-theme"
  theme_select_notify "${style_icon}" "Style ${selection} applied..."
  exit 0
}

ensure_theme_thumbs() {
  local ext="${1:-sqre}"
  local -a missing_walls=()
  local wall=""
  local hash=""
  local thumb=""
  local queue_script="${LIB_DIR}/hypr/wallpaper/wallcache.daemon.sh"

  for wall in "${thmWall[@]}"; do
    [[ -n "${wall}" && -r "${wall}" ]] || continue
    hash="$(set_hash "${wall}")" || continue
    thumb="${WALLPAPER_THUMB_DIR}/${hash}.${ext}"
    [[ -e "${thumb}" ]] || missing_walls+=("${wall}")
  done

  ((${#missing_walls[@]} > 0)) || return 0

  local -a cache_args=()
  for wall in "${missing_walls[@]}"; do
    cache_args+=(-w "${wall}")
  done

  if [[ -x "${queue_script}" ]]; then
    "${queue_script}" --enqueue "${cache_args[@]}" &>/dev/null &
  else
    "${LIB_DIR}/hypr/wallpaper/sww-wallcache.sh" "${cache_args[@]}" &>/dev/null &
  fi
}

resolve_theme_selector_style() {
  local font_scale="$1"
  local theme_style="${ROFI_THEME_STYLE:-$(get_hypr_conf "ROFI_THEME_STYLE")}"
  local hypr_border=2
  local elem_border=$((hypr_border * 2))
  local icon_border=$((elem_border - 4))
  local elm_width=0
  local elm_height=0
  local col_count=0
  local row_count=0

  ((icon_border < 0)) && icon_border=0
  [[ -n "${theme_style}" ]] || theme_style=1
  read -r hypr_border _ _ < <(theme_selector_monitor_metrics)
  elem_border=$((hypr_border * 2))
  icon_border=$((elem_border - 4))
  ((icon_border < 0)) && icon_border=0

  elm_width=$(((16 + 12) * font_scale * 2))
  elm_height=$(((16 + 4) * font_scale * 2))

  case "${theme_style}" in
    2 | quad)
      read -r col_count row_count < <(
        theme_selector_grid_counts "${font_scale}" "${elm_width}" "${elm_height}" 8 16 "" "" 2 4
      )
      printf 'quad\nselector\nwindow{width:100%%;height:100%%;fullscreen:true;background-color:#00000003;}\nlistview{columns:%d;lines:%d;cycle:true;}\nelement{border-radius:%dpx;background-color:@background-alpha;}\nelement-icon{size:16em;border-radius:%dpx 0px 0px %dpx;}\n' \
        "${col_count}" "${row_count}" "${elem_border}" "${icon_border}" "${icon_border}"
      ;;
    *)
      read -r col_count row_count < <(
        theme_selector_grid_counts "${font_scale}" "${elm_width}" "${elm_height}" 8 16 2 "" 2 4
      )
      printf 'sqre\nselector\nwindow{width:100%%;height:100%%;fullscreen:true;border-radius:%dpx;}\nlistview{columns:%d;lines:%d;cycle:true;spacing:2.5em;padding:1.5em;}\nelement{border-radius:%dpx;padding:0.5em;}\nelement-icon{size:15.5em;border-radius:%dpx;}\n' \
        "${hypr_border}" "${col_count}" "${row_count}" "${elem_border}" "${icon_border}"
      ;;
  esac
}

theme_menu_entries() {
  local ext="$1"
  local i=0

  while ((i < ${#thmList[@]})); do
    printf '%s\x00icon\x1f%s/%s.%s\n' \
      "${thmList[$i]}" \
      "${WALLPAPER_THUMB_DIR}" \
      "$(set_hash "${thmWall[$i]}")" \
      "${ext}"
    i=$((i + 1))
  done
}

show_theme_selector() {
  local font_scale=""
  local font_name=""
  local font_override=""
  local thmb_extn=""
  local rofi_theme_name=""
  local layout_override=""
  local selection=""

  font_scale="$(rofi_effective_font_scale "${ROFI_THEME_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_THEME_FONT:-$ROFI_FONT}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  mapfile -t selector_data < <(resolve_theme_selector_style "${font_scale}")
  thmb_extn="${selector_data[0]}"
  rofi_theme_name="${selector_data[1]}"
  layout_override="$(printf '%s\n' "${selector_data[@]:2}")"

  get_themes
  ensure_theme_thumbs "${thmb_extn}"

  selection="$(
    theme_menu_entries "${thmb_extn}" | rofi -dmenu -i \
      -theme "$(rofi_resolve_theme "${rofi_theme_name}")" \
      -theme-str "${font_override}" \
      -theme-str "${layout_override}" \
      -select "${HYPR_THEME}"
  )"

  [[ -n "${selection}" ]] || exit 0
  "${LIB_DIR}/hypr/theme/theme.switch.sh" -s "${selection}"
}

case "${1:-}" in
  -m | -s | --select-menu)
    show_style_selector
    ;;
  -*)
    help_message
    ;;
  *)
    show_theme_selector
    ;;
esac
