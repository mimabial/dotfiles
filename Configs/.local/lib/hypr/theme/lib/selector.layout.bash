#!/usr/bin/env bash

THEME_SELECTOR_MENU_RADIUS_MULTIPLIER=5
THEME_SELECTOR_MENU_ICON_OFFSET=5
THEME_SELECTOR_PREVIEW_RADIUS_MULTIPLIER=2
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
  local font_scale="$1" monitor_settings_name="$2"
  local preview_image_size="${ROFI_THEME_MENU_PREVIEW_SIZE:-192}"
  local hidpi_scale="${ROFI_THEME_MENU_HIDPI_SCALE:-2}"
  local theme_menu_icon_size="${ROFI_THEME_MENU_ICON_SIZE:-20}"
  local theme_menu_element_padding="${ROFI_THEME_MENU_ELEMENT_PADDING:-0em}"
  local theme_menu_list_spacing="${ROFI_THEME_MENU_LIST_SPACING:-3em}"
  local theme_menu_list_padding="${ROFI_THEME_MENU_LIST_PADDING:-1em}"
  local -A menu_geometry=()
  [[ "${preview_image_size}" =~ ^[1-9][0-9]*$ ]] || preview_image_size=192
  [[ "${hidpi_scale}" =~ ^[1-9][0-9]*$ ]] || hidpi_scale=2
  [[ "${theme_menu_icon_size}" =~ ^[0-9]+$ ]] || theme_menu_icon_size=20
  menu_geometry=(
    [font_scale]="${font_scale}"
    [element_width]="$((preview_image_size * hidpi_scale))"
    [element_height]="$((preview_image_size * hidpi_scale))"
    [horizontal_padding]=8 [vertical_padding]=16
    [max_columns]=5 [min_rows]=2 [max_rows]=4
  )
  theme_selector_scaled_radii_into menu_geometry "${monitor_settings_name}" \
    "${THEME_SELECTOR_MENU_RADIUS_MULTIPLIER}" "${THEME_SELECTOR_MENU_ICON_OFFSET}"
  theme_selector_grid_counts_into menu_geometry "${monitor_settings_name}" || return 1

  cat <<EOF
window{width:100%;height:100%;fullscreen:true;}
listview{columns:${menu_geometry[columns]};lines:${menu_geometry[rows]};cycle:true;spacing:${theme_menu_list_spacing};padding:${theme_menu_list_padding};}
element{orientation:vertical;border-radius:${menu_geometry[element_radius]}px;padding:${theme_menu_element_padding};}
element-icon{border-radius:${menu_geometry[icon_radius]}px;size:${theme_menu_icon_size}em;}
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
  [[ -n "${theme_style}" ]] || theme_style=1
  theme_selector_scaled_radii_into preview_geometry "$5" \
    "${THEME_SELECTOR_PREVIEW_RADIUS_MULTIPLIER}" "${THEME_SELECTOR_PREVIEW_ICON_OFFSET}"
  rofi_theme_ref=selector

  case "${theme_style}" in
    2 | quad)
      thumbnail_ref=quad
      theme_selector_grid_counts_into preview_geometry "$5" || return 1
      printf -v layout_ref 'window{width:100%%;height:100%%;fullscreen:true;background-color:#00000003;}\nlistview{columns:%d;lines:%d;cycle:true;}\nelement{border-radius:%dpx;background-color:@background-alpha;}\nelement-icon{size:16em;border-radius:%dpx 0px 0px %dpx;}' \
        "${preview_geometry[columns]}" "${preview_geometry[rows]}" "${preview_geometry[element_radius]}" "${preview_geometry[icon_radius]}" "${preview_geometry[icon_radius]}"
      ;;
    *)
      thumbnail_ref=sqre
      preview_geometry[min_columns]=2
      theme_selector_grid_counts_into preview_geometry "$5" || return 1
      printf -v layout_ref 'window{width:100%%;height:100%%;fullscreen:true;border-radius:%dpx;}\nlistview{columns:%d;lines:%d;cycle:true;spacing:2.5em;padding:1.5em;}\nelement{border-radius:%dpx;padding:0.5em;}\nelement-icon{size:15.5em;border-radius:%dpx;}' \
        "${monitor_metrics_ref[border_radius]}" "${preview_geometry[columns]}" "${preview_geometry[rows]}" "${preview_geometry[element_radius]}" "${preview_geometry[element_radius]}"
      ;;
  esac
}
