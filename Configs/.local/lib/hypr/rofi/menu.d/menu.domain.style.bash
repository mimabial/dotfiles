#!/usr/bin/env bash

menu_add_presets() {
  local menu_id="$1" default_icon="$2" kind="$3" extension="$4" icon_key="$5" path="" name="" icon="" line=""
  local pattern="vars\\.set\\(\"${icon_key}\",[[:space:]]*\"([^\"]+)\""
  local -A preset_icons=(
    [animations/blink]="󰈈" [animations/bounce]="󰠆" [animations/default]="󰗘" [animations/disable]="󰏥"
    [animations/flash]="󰉁" [animations/optimized]="󰓅" [animations/vertical]="󰡏"
    [shaders/color-vision]="󰴄" [shaders/grayscale]="󱎖" [shaders/invert-colors]="󰌁"
    [shaders/neutral]="󰜺" [shaders/vibrance]="󰏘"
  )
  local -A seen=()
  shift 5
  for path in "${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/${kind}"/*."${extension}" \
    "${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/${kind}"/*."${extension}"; do
    name="${path##*/}"
    name="${name%."${extension}"}"
    [[ -f "${path}" && -z "${seen[${name}]:-}" && " $* " != *" ${name} "* ]] || continue
    seen["${name}"]=1
    icon="${preset_icons["${kind}/${name}"]:-${default_icon}}"
    while [[ -n "${icon_key}" ]] && IFS= read -r line; do
      [[ "${line}" =~ ${pattern} ]] || continue
      icon="${BASH_REMATCH[1]}"
      break
    done <"${path}"
    menu_add_item "${menu_id}" "${icon}  ${name^}" action "${menu_id}_${name}"
  done
}

menu_opacity_percent() {
  [[ "${REPLY}" =~ ^([0-9]+)(\.([0-9]{0,2}))?$ ]] || { REPLY=auto; return 0; }
  local fraction="${BASH_REMATCH[3]}00"
  REPLY=$((10#${BASH_REMATCH[1]} * 100 + 10#${fraction:0:2}))
}

menu_add_opacity() {
  local menu_id="$1" line="" name=""
  local -A opacity_icons=([Opaque]="󰝤" [Glass]="󱡓" ["Frosted Glass"]="󰂵" [Translucent]="󱎖" [Transparent]="󰄱")
  menu_define "${menu_id}" "Opacity" choice
  menu_add_item "${menu_id}" "󰘮  $2" action "${menu_id}_auto"
  while IFS= read -r line; do
    [[ "${line}" =~ name:\ \"([^\"]+)\",\ value:\ ([0-9.]+) ]] || continue
    name="${BASH_REMATCH[1]}" REPLY="${BASH_REMATCH[2]}"
    menu_opacity_percent
    menu_add_item "${menu_id}" "${opacity_icons[${name}]:-󰃟}  ${name} (${REPLY}%)" action "${menu_id}_${REPLY}"
  done <"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/Opacity.js"
}

style_register_bar_and_dock() {
  menu_define style_bar "Bar"
  menu_add_item style_bar "󰍜  Layout" submenu style_bar_layout
  menu_add_item style_bar "󰃟  Opacity" submenu style_bar_opacity
  menu_add_item style_bar "󰐷  Blur" action style_bar_blur
  menu_add_item style_bar "󰹞  Floating" action style_bar_floating

  menu_define style_dock "Dock"
  menu_add_item style_dock "󰃟  Opacity" submenu style_dock_opacity
  menu_add_item style_dock "󰐷  Blur" action style_dock_blur

  menu_add_opacity style_bar_opacity "Auto (Workflow)"
  menu_add_opacity style_dock_opacity "Auto (Theme)"
}

style_register_bar_layouts() {
  local layout_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/layouts"
  local layout_file="" layout_label="" layout_name=""
  local -a workflow_layouts=()
  local -A layout_icons=([top]="󱔓" [bottom]="󱂩" [macos]="󰀵" [winbar]="󰖳")

  menu_define style_bar_layout "Layout" choice
  read -ra workflow_layouts <<<"$(state_get WORKFLOW_QUICKSHELL_LAYOUT "")"
  for layout_file in "${layout_dir}"/*.json; do
    [[ -f "${layout_file}" ]] || continue
    layout_name="${layout_file##*/}"
    layout_name="${layout_name%.json}"
    ((${#workflow_layouts[@]} == 0)) || [[ " ${workflow_layouts[*]} " == *" ${layout_name} "* ]] || continue
    layout_label="${layout_name//-/ }"
    layout_label="${layout_label^}"
    menu_add_item style_bar_layout "${layout_icons[${layout_name}]:-󰍜}  ${layout_label}" action "style_bar_layout_${layout_name}"
  done
}

style_register_presets() {
  menu_define style_animations "Animations" choice
  menu_add_presets style_animations "󰹑" animations lua ""

  menu_define style_shaders "Shaders" choice
  menu_add_presets style_shaders "󰆗" shaders frag ""

  menu_define style_workflow "Workflow" choice
  menu_add_presets style_workflow "" workflows lua WORKFLOW_ICON gaming powersaver
}

style_register_text_sizes() {
  local size=""

  menu_define style_text_size "Text Size" choice
  for size in $("${HYPR_LIB_DIR}/system/text-size.sh" --list); do
    menu_add_item style_text_size "  ${size} px" action "style_text_size_${size}"
  done
}

style_register_expose() {
  menu_define style_expose "Exposé"
  menu_add_item style_expose "󰍉  Hot Corner" submenu style_expose_hot_corner

  menu_define style_expose_hot_corner "Hot Corner" choice
  menu_add_item style_expose_hot_corner "↖  Top Left" action style_expose_hot_corner_top-left
  menu_add_item style_expose_hot_corner "↗  Top Right" action style_expose_hot_corner_top-right
  menu_add_item style_expose_hot_corner "↙  Bottom Left" action style_expose_hot_corner_bottom-left
  menu_add_item style_expose_hot_corner "↘  Bottom Right" action style_expose_hot_corner_bottom-right
}

menu_register_domain_style() {
  menu_define style "Style"
  menu_add_item style "󰸌  Theme" action style_theme
  menu_add_item style "  Wallpaper" action style_wallpaper
  menu_add_item style "  Color Mode" submenu style_color_mode
  menu_add_item style "󰍜  Bar" submenu style_bar
  menu_add_item style "󰇊  Dock" submenu style_dock
  menu_add_item style "󰕸  Exposé" submenu style_expose
  menu_add_item style "󰹑  Animations" submenu style_animations
  menu_add_item style "󰆗  Shaders" submenu style_shaders
  menu_add_item style "󰏘  Lock Layout" action style_lock_layout
  menu_add_item style "  Workflow" submenu style_workflow
  menu_add_item style "󰩨  Theme Menu Style" action style_theme_menu
  menu_add_item style "󰀻  Launcher Style" action style_launcher
  menu_add_item style "  Font" action style_font
  menu_add_item style "  Text Size" submenu style_text_size

  style_register_bar_and_dock
  style_register_bar_layouts

  menu_define style_color_mode "Color Mode" choice
  menu_add_item style_color_mode "󰸌  Theme Colors" action style_color_mode_source_theme
  menu_add_item style_color_mode "  Wallpaper Colors" action style_color_mode_source_pywal
  menu_add_item style_color_mode "󰖔  Dark" action style_color_mode_dark
  menu_add_item style_color_mode "󰖨  Light" action style_color_mode_light
  menu_add_item style_color_mode "󰔎  Auto" action style_color_mode_auto

  style_register_presets
  style_register_text_sizes
  style_register_expose
}

menu_run_action_style() {
  local action_id="$1"
  local corner=""
  local layout_name=""

  case "${action_id}" in
    style_theme_menu) hyprshell rofi/run-after-close.sh -- hyprshell theme.select.sh -s ;;
    style_launcher) hyprshell rofi/run-after-close.sh -- hyprshell rofi/rofi-launch.sh -s ;;
    style_theme) hyprshell rofi/run-after-close.sh -- hyprshell theme/theme.select.sh ;;
    style_wallpaper) hyprshell rofi/run-after-close.sh -- hyprshell wallpaper select --global ;;
    style_color_mode_source_*) hyprshell theme/color-mode --set "${action_id#style_color_mode_source_}" ;;
    style_color_mode_*) hyprshell theme/color-mode --set "$(state_get selected_color_source theme)" "${action_id#style_color_mode_}" ;;
    style_bar_layout_*)
      layout_name="${action_id#style_bar_layout_}"
      [[ "${layout_name}" =~ ^[a-z0-9_-]+$ ]] || return 1
      hyprshell quickshell/layout set "${layout_name}"
      ;;
    style_bar_blur) quickshell ipc --any-display call bar blur ;;
    style_bar_floating) quickshell ipc --any-display call bar floating ;;
    style_bar_opacity_*) quickshell ipc --any-display call bar opacity "${action_id#style_bar_opacity_}" ;;
    style_dock_opacity_*) quickshell ipc --any-display call dock opacity "${action_id#style_dock_opacity_}" ;;
    style_dock_blur) quickshell ipc --any-display call dock blur ;;
    style_expose_hot_corner_*)
      corner="${action_id#style_expose_hot_corner_}"
      case "${corner}" in
        top-left | top-right | bottom-left | bottom-right) ;;
        *) return 1 ;;
      esac
      quickshell ipc --any-display call expose hotCornerPosition "${corner}" >/dev/null
      quickshell ipc --any-display call expose hotCorner on >/dev/null
      ;;
    style_animations_*) hyprshell animations.sh --set "${action_id#style_animations_}" ;;
    style_shaders_*) hyprshell shaders.sh --set "${action_id#style_shaders_}" ;;
    style_text_size_*) hyprshell system/text-size.sh "${action_id#style_text_size_}" ;;
    style_lock_layout) hyprshell rofi/run-after-close.sh -- hyprshell session/hyprlock.sh --select ;;
    style_workflow_*) hyprshell util/workflows.sh --set "${action_id#style_workflow_}" ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_style

menu_active_style() {
  local target="$1" bar="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/bar.json"
  local dock="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/dock/settings.json"
  local expose="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/expose/settings.json"
  local -a color_modes=(["${STATE_COLOR_MODE_AUTO}"]=auto ["${STATE_COLOR_MODE_DARK}"]=dark ["${STATE_COLOR_MODE_LIGHT}"]=light)

  case "${target}" in
    style_bar_layout_*) menu_choice "${target}" style_bar_layout_ state_get QUICKSHELL_LAYOUT_NAME top ;;
    style_workflow_*) menu_choice "${target}" style_workflow_ state_get HYPR_WORKFLOW default ;;
    style_animations_*) menu_choice "${target}" style_animations_ state_get HYPR_ANIMATION default ;;
    style_shaders_*) menu_choice "${target}" style_shaders_ state_get HYPR_SHADER neutral ;;
    style_text_size_*) menu_choice "${target}" style_text_size_ state_get TEXT_SIZE 12 ;;
    style_color_mode_source_*) menu_choice "${target}" style_color_mode_source_ state_get selected_color_source theme ;;
    style_color_mode_*) menu_state selected_color_mode state_get selected_color_mode "${STATE_COLOR_MODE_DARK}" && [[ "${target#style_color_mode_}" == "${color_modes[REPLY]:-}" ]] ;;
    style_bar_blur) menu_json_flag "${bar}" barBlur true ;;
    style_bar_floating) menu_json_flag "${bar}" barFloating false ;;
    style_bar_opacity_*) menu_json_value "${bar}" barOpacity -1 && menu_opacity_percent && [[ "${target#style_bar_opacity_}" == "${REPLY}" ]] ;;
    style_dock_opacity_*) menu_json_value "${dock}" opacity 1 && menu_opacity_percent && [[ "${target#style_dock_opacity_}" == "${REPLY}" ]] ;;
    style_dock_blur) menu_json_flag "${dock}" blur true ;;
    style_expose_hot_corner_*) menu_json_flag "${expose}" hotCornerEnabled true && menu_json_value "${expose}" hotCornerPosition top-left && [[ "${target#style_expose_hot_corner_}" == "${REPLY}" ]] ;;
    *) return 1 ;;
  esac
}

menu_register_active_check menu_active_style
