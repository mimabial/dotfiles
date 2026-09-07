#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

menu_register_domain_style() {
  local layout_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/layouts"
  local layout_file=""
  local layout_label=""
  local layout_name=""

  menu_define style "Style"
  menu_add_item style "󰸌  Theme" action style_theme
  menu_add_item style "  Wallpaper" action style_wallpaper
  menu_add_item style "  Color Mode" action style_color_mode
  menu_add_item style "󰍜  Bar" submenu style_bar
  menu_add_item style "󰇊  Dock" submenu style_dock
  menu_add_item style "󰕸  Exposé" submenu style_expose
  menu_add_item style "󰹑  Animations" action style_animations
  menu_add_item style "󰏘  Lock Layout" action style_lock_layout
  menu_add_item style "  Workflow" action style_workflow
  menu_add_item style "󰩨  Theme Menu Style" action style_theme_menu
  menu_add_item style "󰀻  Launcher Style" action style_launcher
  menu_add_item style "  Font" action style_font

  menu_define style_bar "Bar"
  menu_add_item style_bar "󰍜  Layout" submenu style_bar_layout
  menu_add_item style_bar "󰂵  Transparency" action style_bar_transparency
  menu_add_item style_bar "󰐷  Blur" action style_bar_blur

  menu_define style_dock "Dock"
  menu_add_item style_dock "󰄶  Position" submenu style_dock_position
  menu_add_item style_dock "󰂵  Transparency" action style_dock_transparency
  menu_add_item style_dock "󰐷  Blur" action style_dock_blur

  menu_define style_dock_position "Position"
  menu_add_item style_dock_position "󰌷  Opposite the Bar" action style_dock_position_link
  menu_add_item style_dock_position "↓  Bottom" action style_dock_position_bottom
  menu_add_item style_dock_position "↑  Top" action style_dock_position_top
  menu_add_item style_dock_position "←  Left" action style_dock_position_left
  menu_add_item style_dock_position "→  Right" action style_dock_position_right

  menu_define style_bar_layout "Layout"
  for layout_file in "${layout_dir}"/*.json; do
    [[ -f "${layout_file}" ]] || continue
    layout_name="${layout_file##*/}"
    layout_name="${layout_name%.json}"
    layout_label="${layout_name//-/ }"
    layout_label="${layout_label^}"
    menu_add_item style_bar_layout "󰍜  ${layout_label}" action "style_bar_layout_${layout_name}"
  done

  menu_define style_expose "Exposé"
  menu_add_item style_expose "󰍉  Hot Corner" submenu style_expose_hot_corner

  menu_define style_expose_hot_corner "Hot Corner"
  menu_add_item style_expose_hot_corner "↖  Top Left" action style_expose_hot_corner_top-left
  menu_add_item style_expose_hot_corner "↗  Top Right" action style_expose_hot_corner_top-right
  menu_add_item style_expose_hot_corner "↙  Bottom Left" action style_expose_hot_corner_bottom-left
  menu_add_item style_expose_hot_corner "↘  Bottom Right" action style_expose_hot_corner_bottom-right
}

menu_run_action_style() {
  local action_id="$1"
  local corner=""
  local edge_name=""
  local layout_name=""

  case "${action_id}" in
    style_theme_menu) hyprshell rofi/run-after-close.sh -- hyprshell theme.select.sh -s ;;
    style_launcher) hyprshell rofi/run-after-close.sh -- hyprshell rofi/rofi-launch.sh -s ;;
    style_theme) hyprshell rofi/run-after-close.sh -- hyprshell theme/theme.select.sh ;;
    style_wallpaper) hyprshell rofi/run-after-close.sh -- hyprshell wallpaper select --global ;;
    style_color_mode) hyprshell rofi/run-after-close.sh -- hyprshell theme/color-mode -m ;;
    style_bar_layout_*)
      layout_name="${action_id#style_bar_layout_}"
      [[ "${layout_name}" =~ ^[a-z0-9_-]+$ ]] || return 1
      hyprshell quickshell/layout set "${layout_name}"
      ;;
    style_bar_transparency) quickshell ipc --any-display call bar transparency ;;
    style_bar_blur) quickshell ipc --any-display call bar blur ;;
    style_dock_transparency) quickshell ipc --any-display call dock transparency ;;
    style_dock_blur) quickshell ipc --any-display call dock blur ;;
    style_dock_position_link) quickshell ipc --any-display call dock link ;;
    style_dock_position_*)
      edge_name="${action_id#style_dock_position_}"
      case "${edge_name}" in
        top | bottom | left | right) ;;
        *) return 1 ;;
      esac
      quickshell ipc --any-display call dock position "${edge_name}"
      ;;
    style_expose_hot_corner_*)
      corner="${action_id#style_expose_hot_corner_}"
      case "${corner}" in
        top-left | top-right | bottom-left | bottom-right) ;;
        *) return 1 ;;
      esac
      quickshell ipc --any-display call expose hotCornerPosition "${corner}" >/dev/null
      quickshell ipc --any-display call expose hotCorner on >/dev/null
      ;;
    style_animations) hyprshell rofi/run-after-close.sh -- hyprshell animations.sh --select ;;
    style_lock_layout) hyprshell rofi/run-after-close.sh -- hyprshell session/hyprlock.sh --select ;;
    style_workflow) hyprshell rofi/run-after-close.sh -- hyprshell util/workflows.sh --select ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_style
