#!/usr/bin/env bash

menu_register_domain_trigger() {
  menu_define trigger "Trigger"
  menu_add_item trigger "  Capture" submenu trigger_capture
  menu_add_item trigger "󰔎  Toggle" submenu trigger_toggle

  menu_define trigger_capture "Capture"
  menu_add_item trigger_capture "  Screenshot" submenu trigger_screenshot
  menu_add_item trigger_capture "  Screenrecord" submenu trigger_screenrecord
  menu_add_item trigger_capture "  Color Hex" action trigger_color_picker

  menu_define trigger_screenshot "Screenshot"
  menu_add_item trigger_screenshot "  Snap with Editing" action trigger_screenshot_edit
  menu_add_item trigger_screenshot "  Straight to Clipboard" action trigger_screenshot_clipboard

  menu_define trigger_screenrecord "Screenrecord"
  menu_add_item trigger_screenrecord "  Window" submenu trigger_screenrecord_window
  menu_add_item trigger_screenrecord "  Region" submenu trigger_screenrecord_region
  menu_add_item trigger_screenrecord "  Display" submenu trigger_screenrecord_display

  menu_define trigger_screenrecord_window "Audio"
  menu_add_item trigger_screenrecord_window "  No Audio" action trigger_screenrecord_window
  menu_add_item trigger_screenrecord_window "  With Audio" action trigger_screenrecord_window_audio

  menu_define trigger_screenrecord_region "Audio"
  menu_add_item trigger_screenrecord_region "  No Audio" action trigger_screenrecord_region
  menu_add_item trigger_screenrecord_region "  With Audio" action trigger_screenrecord_region_audio

  menu_define trigger_screenrecord_display "Audio"
  menu_add_item trigger_screenrecord_display "  No Audio" action trigger_screenrecord_display
  menu_add_item trigger_screenrecord_display "  With Audio" action trigger_screenrecord_display_audio

  menu_define trigger_toggle "Toggle"
  menu_add_item trigger_toggle "󰔎  Nightlight" action trigger_toggle_nightlight
  menu_add_item trigger_toggle "󱫖  Keep Awake" action trigger_toggle_keep_awake
  menu_add_item trigger_toggle "󰍜  Waybar" action trigger_toggle_waybar
}

menu_run_action_trigger() {
  local action_id="$1"

  case "${action_id}" in
    trigger_screenshot_edit) hyprshell capture/screenshot.sh smart ;;
    trigger_screenshot_clipboard) hyprshell capture/screenshot.sh smart clipboard ;;
    trigger_screenrecord_window) hyprshell capture/screenrecord.sh --start --window ;;
    trigger_screenrecord_window_audio) hyprshell capture/screenrecord.sh --start --window --audio ;;
    trigger_screenrecord_region) hyprshell capture/screenrecord.sh --start --region ;;
    trigger_screenrecord_region_audio) hyprshell capture/screenrecord.sh --start --region --audio ;;
    trigger_screenrecord_display) hyprshell capture/screenrecord.sh --start --output ;;
    trigger_screenrecord_display_audio) hyprshell capture/screenrecord.sh --start --output --audio ;;
    trigger_color_picker) hyprshell rofi/colorpicker.sh ;;
    trigger_toggle_nightlight) hyprshell hyprsunset --toggle && pkill -SIGUSR2 waybar ;;
    trigger_toggle_keep_awake) hyprshell session/toggle-keep-awake.sh ;;
    trigger_toggle_waybar) hyprshell waybar/waybar.py --hide ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_trigger
