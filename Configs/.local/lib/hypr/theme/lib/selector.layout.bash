#!/usr/bin/env bash

THEME_SELECTOR_MENU_RADIUS_MULTIPLIER=5
THEME_SELECTOR_MENU_ICON_OFFSET=5
THEME_SELECTOR_PREVIEW_ICON_OFFSET=4

theme_selector_monitor_metrics_into() {
  local -n monitor_metrics_ref="$1"
  local logical_width="" logical_height=""
  read -r logical_width logical_height < <(rofi_focused_monitor_logical_size)
  monitor_metrics_ref=(
    [border_radius]="$(rofi_default_border_radius 2)"
    [logical_width]="${logical_width}"
    [logical_height]="${logical_height}"
  )
}

theme_selector_scaled_radii_into() {
  local -n radii_ref="$1" monitor_metrics_ref="$2"
  local element_multiplier="$3" icon_offset="$4"
  local base_radius="${monitor_metrics_ref[border_radius]}"
  [[ "${base_radius}" =~ ^[0-9]+$ ]] || base_radius=0
  radii_ref[element_radius]=$((base_radius * element_multiplier))
  radii_ref[icon_radius]=$((radii_ref[element_radius] - icon_offset))
  ((radii_ref[icon_radius] < 0)) && radii_ref[icon_radius]=0
  return 0
}

theme_selector_grid_counts_into() {
  local -n grid_ref="$1" monitor_metrics_ref="$2"
  local available_width=$((monitor_metrics_ref[logical_width] - grid_ref[horizontal_padding] * grid_ref[font_scale]))
  local available_height=$((monitor_metrics_ref[logical_height] - grid_ref[vertical_padding] * grid_ref[font_scale]))
  ((grid_ref[element_width] > 0 && grid_ref[element_height] > 0)) || return 1
  grid_ref[columns]=$((available_width / grid_ref[element_width]))
  grid_ref[rows]=$((available_height / grid_ref[element_height]))
  [[ -n "${grid_ref[min_columns]:-}" ]] && ((grid_ref[columns] < grid_ref[min_columns])) && grid_ref[columns]="${grid_ref[min_columns]}"
  [[ -n "${grid_ref[max_columns]:-}" ]] && ((grid_ref[columns] > grid_ref[max_columns])) && grid_ref[columns]="${grid_ref[max_columns]}"
  [[ -n "${grid_ref[min_rows]:-}" ]] && ((grid_ref[rows] < grid_ref[min_rows])) && grid_ref[rows]="${grid_ref[min_rows]}"
  [[ -n "${grid_ref[max_rows]:-}" ]] && ((grid_ref[rows] > grid_ref[max_rows])) && grid_ref[rows]="${grid_ref[max_rows]}"
  return 0
}

theme_style_picker_layout() {
  local -n monitor_metrics_ref="$1"
  local theme_menu_icon_size="${ROFI_THEME_MENU_ICON_SIZE:-20}"
  local -A menu_geometry=([columns]=2 [rows]=1)
  [[ "${theme_menu_icon_size}" =~ ^[0-9]+$ ]] || theme_menu_icon_size=20
  menu_geometry[element_width]=$((monitor_metrics_ref[logical_width] / menu_geometry[columns]))
  menu_geometry[element_height]="${monitor_metrics_ref[logical_height]}"
  local icon_size="(${theme_menu_icon_size}em min ${menu_geometry[element_width]}px min ${menu_geometry[element_height]}px)"
  theme_selector_scaled_radii_into menu_geometry "$1" \
    "${THEME_SELECTOR_MENU_RADIUS_MULTIPLIER}" "${THEME_SELECTOR_MENU_ICON_OFFSET}"

  cat <<EOF
window{width:100%;height:100%;fullscreen:true;}
mainbox{children:[frame];spacing:0px;}
frame{spacing:0px;}
inputbar{enabled:false;}
listview{columns:${menu_geometry[columns]};lines:${menu_geometry[rows]};cycle:true;fixed-columns:true;fixed-height:true;spacing:0px;padding:0px;scrollbar:false;}
element{orientation:vertical;border-radius:0px;padding:calc((${menu_geometry[element_height]}px - ${icon_size}) / 2) 0px;}
element-icon{border-radius:${menu_geometry[icon_radius]}px;size:calc(${icon_size});}
element-text{enabled:false;}
EOF
}

theme_pack_picker_layout_into() {
  local -n thumbnail_ref="$1" rofi_theme_ref="$2" layout_ref="$3"
  local font_scale="$4"
  local theme_style="${ROFI_THEME_STYLE:-$(hypr_theme_variable "ROFI_THEME_STYLE")}"
  local -n monitor_metrics_ref="$5"
  local -A preview_geometry=(
    [font_scale]="${font_scale}"
    [element_width_em]=28 [element_height_em]=20
    [horizontal_padding]=8 [vertical_padding]=16 [min_rows]=2 [max_rows]=4
  )
  preview_geometry[element_width]=$((preview_geometry[element_width_em] * font_scale * ROFI_EM_PX_PER_SCALE))
  preview_geometry[element_height]=$((preview_geometry[element_height_em] * font_scale * ROFI_EM_PX_PER_SCALE))
  [[ -n "${theme_style}" ]] || theme_style=square
  theme_selector_scaled_radii_into preview_geometry "$5" \
    "${ROFI_IMAGE_TILE_RADIUS_MULTIPLIER}" "${THEME_SELECTOR_PREVIEW_ICON_OFFSET}"
  rofi_theme_ref=selector

  case "${theme_style}" in
    faded | 2 | quad)
      thumbnail_ref=quad
      declare -F wallcache_write_masked_thumbnail >/dev/null || source "${HYPR_LIB_DIR}/wallpaper/cache/render.bash" || return 1
      local list_spacing_em=2.5 list_padding_em=1.5 target_columns=3 target_rows=3
      preview_geometry[horizontal_padding]=$((preview_geometry[horizontal_padding] / 2))
      preview_geometry[element_width]=$(((monitor_metrics_ref[logical_width] - preview_geometry[horizontal_padding] * font_scale) / target_columns))
      preview_geometry[element_height]=$(((monitor_metrics_ref[logical_height] - preview_geometry[vertical_padding] * font_scale) / target_rows))
      theme_selector_grid_counts_into preview_geometry "$5" || return 1
      printf -v layout_ref '%s\n' \
        'window{width:100%;height:100%;fullscreen:true;background-color:#00000003;}' \
        "frame{expand:false;width:$((preview_geometry[element_width] * preview_geometry[columns]))px;}" \
        'spacer{expand:true;}' \
        "listview{columns:${preview_geometry[columns]};lines:${preview_geometry[rows]};cycle:true;spacing:${list_spacing_em}em;padding:${list_padding_em}em;}" \
        "element{border-radius:${preview_geometry[element_radius]}px;background-color:@background-alpha;}" \
        "element-icon{size:${preview_geometry[element_height]}px;margin:0px calc(${preview_geometry[element_height]}px * $((WALLCACHE_QUAD_CLEAR_FROM_PX - WALLCACHE_SQUARE_PX)) / ${WALLCACHE_SQUARE_PX}) 0px 0px;border-radius:${preview_geometry[icon_radius]}px 0px 0px ${preview_geometry[icon_radius]}px;}" \
        'element-text{expand:true;}'
      ;;
    *)
      thumbnail_ref=sqre
      local target_columns=3 target_rows=3 element_padding_em=0.5
      preview_geometry[element_width]=$(((monitor_metrics_ref[logical_width] - preview_geometry[horizontal_padding] * font_scale) / target_columns))
      preview_geometry[element_height]=$(((monitor_metrics_ref[logical_height] - preview_geometry[vertical_padding] * font_scale) / target_rows))
      preview_geometry[min_columns]=2
      theme_selector_grid_counts_into preview_geometry "$5" || return 1
      printf -v layout_ref 'window{width:100%%;height:100%%;fullscreen:true;border-radius:%dpx;}\nlistview{columns:%d;lines:%d;cycle:true;spacing:2.5em;padding:1.5em;}\nelement{border-radius:%dpx;padding:%sem;}\nelement-icon{size:calc(%dpx - %sem * 2);border-radius:%dpx;}' \
        "${monitor_metrics_ref[border_radius]}" "${preview_geometry[columns]}" "${preview_geometry[rows]}" "${preview_geometry[element_radius]}" "${element_padding_em}" "${preview_geometry[element_height]}" "${element_padding_em}" "${preview_geometry[element_radius]}"
      ;;
  esac
}
