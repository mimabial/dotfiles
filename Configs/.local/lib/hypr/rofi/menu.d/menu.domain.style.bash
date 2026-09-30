#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

menu_add_presets() {
  local menu_id="$1" icon="$2" kind="$3" path="" name=""
  local -A seen=()
  shift 3
  for path in "${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/${kind}"/*.lua \
    "${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}/${kind}"/*.lua; do
    name="${path##*/}"
    name="${name%.lua}"
    [[ -f "${path}" && -z "${seen[${name}]:-}" && " $* " != *" ${name} "* ]] || continue
    seen["${name}"]=1
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
  menu_define "${menu_id}" "Opacity" choice
  menu_add_item "${menu_id}" "󰃟  $2" action "${menu_id}_auto"
  while IFS= read -r line; do
    [[ "${line}" =~ name:\ \"([^\"]+)\",\ value:\ ([0-9.]+) ]] || continue
    name="${BASH_REMATCH[1]}" REPLY="${BASH_REMATCH[2]}"
    menu_opacity_percent
    menu_add_item "${menu_id}" "󰃟  ${name} (${REPLY}%)" action "${menu_id}_${REPLY}"
  done <"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/Opacity.js"
}

menu_register_domain_style() {
  local layout_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/layouts"
  local layout_file=""
  local layout_label=""
  local size=""
  local layout_name=""

  menu_define style "Style"
  menu_add_item style "󰸌  Theme" action style_theme
  menu_add_item style "  Wallpaper" action style_wallpaper
  menu_add_item style "  Color Mode" submenu style_color_mode
  menu_add_item style "󰍜  Bar" submenu style_bar
  menu_add_item style "󰇊  Dock" submenu style_dock
  menu_add_item style "󰕸  Exposé" submenu style_expose
  menu_add_item style "󰹑  Animations" submenu style_animations
  menu_add_item style "󰏘  Lock Layout" action style_lock_layout
  menu_add_item style "  Workflow" submenu style_workflow
  menu_add_item style "󰩨  Theme Menu Style" action style_theme_menu
  menu_add_item style "󰀻  Launcher Style" action style_launcher
  menu_add_item style "  Font" action style_font
  menu_add_item style "  Text Size" submenu style_text_size

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

  menu_define style_bar_layout "Layout" choice
  for layout_file in "${layout_dir}"/*.json; do
    [[ -f "${layout_file}" ]] || continue
    layout_name="${layout_file##*/}"
    layout_name="${layout_name%.json}"
    layout_label="${layout_name//-/ }"
    layout_label="${layout_label^}"
    menu_add_item style_bar_layout "󰍜  ${layout_label}" action "style_bar_layout_${layout_name}"
  done

  menu_define style_color_mode "Color Mode" choice
  menu_add_item style_color_mode "󰸌  Theme Colors" action style_color_mode_source_theme
  menu_add_item style_color_mode "  Wallpaper Colors" action style_color_mode_source_pywal
  menu_add_item style_color_mode "󰖔  Dark" action style_color_mode_dark
  menu_add_item style_color_mode "󰖨  Light" action style_color_mode_light
  menu_add_item style_color_mode "󰔎  Auto" action style_color_mode_auto

  menu_define style_animations "Animations" choice
  menu_add_presets style_animations "󰹑" animations

  menu_define style_workflow "Workflow" choice
  menu_add_presets style_workflow "" workflows gaming powersaver

  menu_define style_text_size "Text Size" choice
  for size in $("${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/text-size.sh" --list); do
    menu_add_item style_text_size "  ${size} px" action "style_text_size_${size}"
  done

  menu_define style_expose "Exposé"
  menu_add_item style_expose "󰍉  Hot Corner" submenu style_expose_hot_corner

  menu_define style_expose_hot_corner "Hot Corner" choice
  menu_add_item style_expose_hot_corner "↖  Top Left" action style_expose_hot_corner_top-left
  menu_add_item style_expose_hot_corner "↗  Top Right" action style_expose_hot_corner_top-right
  menu_add_item style_expose_hot_corner "↙  Bottom Left" action style_expose_hot_corner_bottom-left
  menu_add_item style_expose_hot_corner "↘  Bottom Right" action style_expose_hot_corner_bottom-right
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
  local -a color_modes=([1]=auto [2]=dark [3]=light)

  case "${target}" in
    style_bar_layout_*) menu_choice "${target}" style_bar_layout_ state_get QUICKSHELL_LAYOUT_NAME top ;;
    style_workflow_*) menu_choice "${target}" style_workflow_ state_get HYPR_WORKFLOW default ;;
    style_animations_*) menu_choice "${target}" style_animations_ state_get HYPR_ANIMATION default ;;
    style_text_size_*) menu_choice "${target}" style_text_size_ state_get TEXT_SIZE 12 ;;
    style_color_mode_source_*) menu_choice "${target}" style_color_mode_source_ state_get selected_color_source theme ;;
    style_color_mode_*) menu_state selected_color_mode state_get selected_color_mode 2 && [[ "${target#style_color_mode_}" == "${color_modes[REPLY]:-}" ]] ;;
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
