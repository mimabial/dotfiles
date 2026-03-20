#!/usr/bin/env bash

#// set variables

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

rofiAssetDir="$(rofi_shared_dir)/assets"

hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
hypr_border=${hypr_border:-2}

#// scale for monitor
mon_data=$(hyprctl -j monitors)
mon_x_res=$(jq '.[] | select(.focused==true) | if (.transform % 2 == 0) then .width else .height end' <<<"${mon_data}")
mon_y_res=$(jq '.[] | select(.focused==true) | if (.transform % 2 == 0) then .height else .width end' <<<"${mon_data}")
mon_scale=$(jq '.[] | select(.focused==true) | .scale' <<<"${mon_data}" | sed "s/\.//")

# Add fallback size
mon_x_res=${mon_x_res:-1920}
mon_y_res=${mon_y_res:-1080}
mon_scale=${mon_scale:-1}

mon_x_res=$((mon_x_res * 100 / mon_scale))
mon_y_res=$((mon_y_res * 100 / mon_scale))

theme_select_notify() {
  command -v dunstify >/dev/null 2>&1 || return 0

  local icon_path="$1"
  shift
  local -a args=(
    -a "Theme select"
    -t 2000
    -r 92
  )

  [[ -n "${icon_path}" ]] && args+=(-i "${icon_path}")
  dunstify "${args[@]}" "$@"
}

selector_menu() {
  # ============================================================================
  # Layout Constants
  # ============================================================================
  # Theme menu (-s) size controls. These are isolated from the fullscreen
  # theme picker below so changing them only affects `theme.select.sh -s`.
  local preview_image_size="${ROFI_THEME_MENU_PREVIEW_SIZE:-192}"
  local hidpi_scale="${ROFI_THEME_MENU_HIDPI_SCALE:-2}"
  local theme_menu_icon_size="${ROFI_THEME_MENU_ICON_SIZE:-20}"
  local theme_menu_element_padding="${ROFI_THEME_MENU_ELEMENT_PADDING:-0em}"
  local theme_menu_list_spacing="${ROFI_THEME_MENU_LIST_SPACING:-3em}"
  local theme_menu_list_padding="${ROFI_THEME_MENU_LIST_PADDING:-1em}"
  # Maximum columns/rows to prevent overly dense layouts
  local -r MAX_COLUMNS=5
  local -r MIN_ROWS=2
  local -r MAX_ROWS=4
  # Padding around content (in font_scale units)
  local -r HORIZONTAL_PADDING=8
  local -r VERTICAL_PADDING=16
  # Border multiplier relative to Hyprland rounding
  local -r BORDER_MULTIPLIER=5

  [[ "${preview_image_size}" =~ ^[0-9]+$ ]] || preview_image_size=192
  [[ "${hidpi_scale}" =~ ^[0-9]+$ ]] || hidpi_scale=2
  [[ "${theme_menu_icon_size}" =~ ^[0-9]+$ ]] || theme_menu_icon_size=20

  #// set rofi scaling
  font_scale="${ROFI_THEME_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  # set font name
  font_name=${ROFI_THEME_MENU_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}

  # set rofi font override
  font_override="* {font: \"${font_name} ${font_scale}\";}"

  elem_border=$((hypr_border * BORDER_MULTIPLIER))
  icon_border=$((elem_border - 5))
  elm_width=$((preview_image_size * hidpi_scale))
  elm_height=$((preview_image_size * hidpi_scale))
  max_avail_x=$((mon_x_res - (HORIZONTAL_PADDING * font_scale)))
  max_avail_y=$((mon_y_res - (VERTICAL_PADDING * font_scale)))
  col_count=$((max_avail_x / elm_width))
  row_count=$((max_avail_y / elm_height))
  [[ "${col_count}" -gt ${MAX_COLUMNS} ]] && col_count=${MAX_COLUMNS}
  [[ "${row_count}" -lt ${MIN_ROWS} ]] && row_count=${MIN_ROWS}
  [[ "${row_count}" -gt ${MAX_ROWS} ]] && row_count=${MAX_ROWS}

  r_override="window{width:100%;height:100%;fullscreen:true;}
                listview{columns:${col_count};lines:${row_count};cycle:true;spacing:${theme_menu_list_spacing};padding:${theme_menu_list_padding};}
                element{orientation:vertical;border-radius:${elem_border}px;padding:${theme_menu_element_padding};}
                element-icon{border-radius:${icon_border}px;size:${theme_menu_icon_size}em;}
                element-text{enabled:false;}"

  #// launch rofi menu
  RofiSel=$(
    rofi_list_asset_files 'theme_style_*' \
      | awk -F '[_.]' '{print $((NF - 1))}' \
      | while read -r styleNum; do
        echo -en "${styleNum}\x00icon\x1f$(rofi_resolve_asset "theme_style_${styleNum}.png")\n"
      done | sort -n \
      | rofi -dmenu -i \
        -theme "$(rofi_resolve_theme "${ROFI_THEME_MENU_STYLE:-theme_select}")" \
        -theme-str "${font_override}" \
        -theme-str "${r_override}" \
        -select "${ROFI_THEME_STYLE}"
  )

  #// apply selected theme
  if [ -n "${RofiSel}" ]; then
    #// save selection in config file
    state_set "ROFI_THEME_STYLE" "${RofiSel}" "staterc"

    #// notify the user
    local style_icon
    style_icon="$(rofi_resolve_asset "theme_style_${RofiSel}.png")"
    [[ ! -f "${style_icon}" ]] && style_icon="preferences-desktop-theme"
    theme_select_notify "${style_icon}" "Style ${RofiSel} applied..."
  fi
  exit 0
}

ensure_theme_thumbs() {
  local ext="${1}"
  [[ -z "${ext}" ]] && ext="sqre"
  local -a missing_walls=()
  local wall hash thumb

  for wall in "${thmWall[@]}"; do
    [[ -n "${wall}" ]] || continue
    [[ -r "${wall}" ]] || continue
    hash="$(set_hash "${wall}")" || continue
    thumb="${WALLPAPER_THUMB_DIR}/${hash}.${ext}"
    [[ -e "${thumb}" ]] || missing_walls+=("${wall}")
  done

  if ((${#missing_walls[@]} > 0)); then
    local -a cache_args=()
    local queue_script="${LIB_DIR}/hypr/wallpaper/wallcache.daemon.sh"
    for wall in "${missing_walls[@]}"; do
      cache_args+=(-w "${wall}")
    done
    if [[ -x "${queue_script}" ]]; then
      "${queue_script}" --enqueue "${cache_args[@]}" &>/dev/null &
    else
      "${LIB_DIR}/hypr/wallpaper/swwwallcache.sh" "${cache_args[@]}" &>/dev/null &
    fi
  fi
}

help_message() {
  cat <<HELP
Usage: $(basename "${0}") --select-menu|-s  [style]

menu style:
--select-menu|-s        Select a menu style for this program

selector style:
quad|2      quad style
square|1    square style 

HELP
  exit 0
}

case "$1" in

  -m | -s | --select-menu)
    selector_menu
    ;;
  -*)
    help_message
    ;;

  *)

    #// set rofi scaling
    # shellcheck disable=SC2153
    font_scale="${ROFI_THEME_SCALE}"
    [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

    # set font name
    font_name=${ROFI_THEME_FONT:-$ROFI_FONT}
    font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
    font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
    font_name=${font_name:-$(get_hyprConf "FONT")}
    font_name=${font_name:-monospace}

    # set rofi font override
    font_override="* {font: \"${font_name} ${font_scale}\";}"

    # shellcheck disable=SC2154
    elem_border=$((hypr_border * 2))
    icon_border=$((elem_border - 5))
    [[ "${icon_border}" -lt 0 ]] && icon_border=0

    #// generate config

    # ROFI_THEME_STYLE is loaded from staterc via export_hypr_config
    [[ -z "${ROFI_THEME_STYLE}" ]] && ROFI_THEME_STYLE="$(get_hyprConf "ROFI_THEME_STYLE")"
    [[ -z "${ROFI_THEME_STYLE}" ]] && ROFI_THEME_STYLE="1"
    # shellcheck disable=SC2154
    case "${ROFI_THEME_STYLE}" in
      2 | "quad") # adapt to style 2
        elm_width=$(((16 + 12) * font_scale * 2))
        elm_height=$(((16 + 4) * font_scale * 2))
        max_avail_x=$((mon_x_res - (8 * font_scale)))
        max_avail_y=$((mon_y_res - (16 * font_scale)))
        col_count=$((max_avail_x / elm_width))
        row_count=$((max_avail_y / elm_height))
        [[ "${row_count}" -lt 2 ]] && row_count=2
        [[ "${row_count}" -gt 4 ]] && row_count=4
        r_override="window{width:100%;height:100%;fullscreen:true;background-color:#00000003;}
                            listview{columns:${col_count};lines:${row_count};cycle:true;}
                            element{border-radius:${elem_border}px;background-color:@background-alpha;}
                            element-icon{size:16em;border-radius:${icon_border}px 0px 0px ${icon_border}px;}"
        thmbExtn="quad"
        ROFI_THEME_STYLE="selector"
        ;;
      1 | "square") # default to style 1
        elm_width=$(((16 + 12) * font_scale * 2))
        elm_height=$(((16 + 4) * font_scale * 2))
        max_avail_x=$((mon_x_res - (8 * font_scale)))
        max_avail_y=$((mon_y_res - (16 * font_scale)))
        col_count=$((max_avail_x / elm_width))
        row_count=$((max_avail_y / elm_height))
        [[ "${col_count}" -lt 2 ]] && col_count=2
        [[ "${row_count}" -lt 2 ]] && row_count=2
        [[ "${row_count}" -gt 4 ]] && row_count=4
        r_override="window{width:100%;height:100%;fullscreen:true;border-radius:${hypr_border}px;}
                            listview{columns:${col_count};lines:${row_count};cycle:true;spacing:6em;padding:3em;}
                            element{border-radius:${elem_border}px;padding:0.5em;}
                            element-icon{size:16em;border-radius:${icon_border}px;}"
        thmbExtn="sqre"
        ROFI_THEME_STYLE="selector"
        ;;
    esac
    ;;

esac
#// launch rofi menu

get_themes
ensure_theme_thumbs "${thmbExtn:-sqre}"
# shellcheck disable=SC2154
selected_theme_name=$(
  i=0
  while [ "${i}" -lt ${#thmList[@]} ]; do
    echo -en "${thmList[$i]}\x00icon\x1f${WALLPAPER_THUMB_DIR}/$(set_hash "${thmWall[$i]}").${thmbExtn:-sqre}\n"
    i=$((i + 1))
  done | rofi -dmenu -i \
    -theme "$(rofi_resolve_theme "${ROFI_THEME_STYLE:-selector}")" \
    -theme-str "${font_override}" \
    -theme-str "${r_override}" \
    -select "${HYPR_THEME}"
)

#// apply theme

if [ -n "${selected_theme_name}" ]; then
  "${LIB_DIR}/hypr/theme/theme.switch.sh" -s "${selected_theme_name}"
fi
