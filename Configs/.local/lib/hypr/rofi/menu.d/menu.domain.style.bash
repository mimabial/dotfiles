#!/usr/bin/env bash

menu_register_domain_style() {
  menu_define style "Style"
  menu_add_item style "󰸌  Theme" action style_theme
  menu_add_item style "  Wallpaper" action style_wallpaper
  menu_add_item style "  Color Mode" action style_color_mode
  menu_add_item style "󰍜  Waybar Layout" action style_waybar
  menu_add_item style "󰹑  Animations" action style_animations
  menu_add_item style "󰏘  Lock Layout" action style_lock_layout
  menu_add_item style "  Workflow" action style_workflow
  menu_add_item style "󰩨  Theme Menu Style" action style_theme_menu
  menu_add_item style "󰀻  Launcher Style" action style_launcher
  menu_add_item style "  Font" action style_font
}

menu_run_action_style() {
  local action_id="$1"

  case "${action_id}" in
    style_theme_menu) hyprshell theme.select.sh -s ;;
    style_launcher) hyprshell rofi/rofi-launch.sh -s ;;
    style_theme) hyprshell theme/theme.select.sh ;;
    style_wallpaper) hyprshell wallpaper select --global ;;
    style_color_mode) hyprshell color-mode.sh -m ;;
    style_waybar) hyprshell waybar.py --select ;;
    style_animations) hyprshell animations.sh --select ;;
    style_lock_layout) hyprshell hyprlock.sh --select ;;
    style_workflow) hyprshell util/workflows.sh --select ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_style
