#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

trigger_rofi_layers_present() {
  local layers_json=""

  if ! layers_json="$(hyprctl -j layers 2>/dev/null)"; then
    return 2
  fi

  if ! jq -e '
    to_entries
    | any(
        (.value.levels // {})
        | .[]?[]?
        | select((.namespace? // "") == "rofi")
      )
  ' <<<"${layers_json}" >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

trigger_wait_for_rofi_layers_gone() {
  local deadline=0
  local empty_polls=0

  deadline=$((SECONDS + 3))

  while ((SECONDS < deadline)); do
    if trigger_rofi_layers_present; then
      empty_polls=0
    else
      case "$?" in
        1)
          ((empty_polls += 1))
          if ((empty_polls >= 2)); then
            return 0
          fi
          ;;
        *)
          empty_polls=0
          ;;
      esac
    fi

    sleep 0.03
  done

  return 1
}

trigger_spawn_detached() {
  (
    pkill -u "${UID:-$(id -u)}" -x rofi >/dev/null 2>&1 || true
    trigger_wait_for_rofi_layers_gone
    exec "$@"
  ) >/dev/null 2>&1 </dev/null &
}

menu_register_domain_trigger() {
  menu_define trigger "Trigger"
  menu_add_item trigger "  Capture" submenu trigger_capture
  menu_add_item trigger "󰕍  Share" submenu trigger_share
  menu_add_item trigger "󰔎  Toggle" submenu trigger_toggle

  menu_define trigger_capture "Capture"
  menu_add_item trigger_capture "  Screenshot" submenu trigger_screenshot
  menu_add_item trigger_capture "  Screenrecord" submenu trigger_screenrecord
  menu_add_item trigger_capture "  Color Picker" action trigger_color_picker

  menu_define trigger_screenshot "Screenshot"
  menu_add_item trigger_screenshot "  Smart with Editing" action trigger_screenshot_edit
  menu_add_item trigger_screenshot "  Smart to Clipboard" action trigger_screenshot_clipboard
  menu_add_item trigger_screenshot "  Smart Save" action trigger_screenshot_save
  menu_add_item trigger_screenshot "󱂬  Window" action trigger_screenshot_window
  menu_add_item trigger_screenshot "󰍹  Focused Monitor" action trigger_screenshot_monitor
  menu_add_item trigger_screenshot "󰹑  All Outputs" action trigger_screenshot_all
  menu_add_item trigger_screenshot "󱉶  OCR Area" action trigger_screenshot_ocr

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

  menu_define trigger_share "Share"
  menu_add_item trigger_share "  Clipboard" action trigger_share_clipboard
  menu_add_item trigger_share "󰈔  File" action trigger_share_file
  menu_add_item trigger_share "󰉋  Folder" action trigger_share_folder

  menu_define trigger_toggle "Toggle"
  menu_add_item trigger_toggle "󰔎  Nightlight" action trigger_toggle_nightlight
  menu_add_item trigger_toggle "󱫖  Keep Awake" action trigger_toggle_keep_awake
  menu_add_item trigger_toggle "󰍜  Waybar" action trigger_toggle_waybar
}

menu_run_action_trigger() {
  local action_id="$1"

  case "${action_id}" in
    trigger_screenshot_edit) trigger_spawn_detached hyprshell capture/screenshot.sh smart ;;
    trigger_screenshot_clipboard) trigger_spawn_detached hyprshell capture/screenshot.sh smart clipboard ;;
    trigger_screenshot_save) trigger_spawn_detached hyprshell capture/screenshot.sh smart save ;;
    trigger_screenshot_window) trigger_spawn_detached hyprshell capture/screenshot.sh w ;;
    trigger_screenshot_monitor) trigger_spawn_detached hyprshell capture/screenshot.sh m ;;
    trigger_screenshot_all) trigger_spawn_detached hyprshell capture/screenshot.sh p ;;
    trigger_screenshot_ocr) trigger_spawn_detached hyprshell capture/screenshot.sh ocr ;;
    trigger_screenrecord_window) hyprshell capture/screenrecord.sh --start --window ;;
    trigger_screenrecord_window_audio) hyprshell capture/screenrecord.sh --start --window --audio ;;
    trigger_screenrecord_region) hyprshell capture/screenrecord.sh --start --region ;;
    trigger_screenrecord_region_audio) hyprshell capture/screenrecord.sh --start --region --audio ;;
    trigger_screenrecord_display) hyprshell capture/screenrecord.sh --start --output ;;
    trigger_screenrecord_display_audio) hyprshell capture/screenrecord.sh --start --output --audio ;;
    trigger_share_clipboard) trigger_spawn_detached hyprshell util/share.sh clipboard ;;
    trigger_share_file) trigger_spawn_detached uwsm-app -- tui-terminal-exec --hypr-profile dialog --app-id org.tui.Share --title Share -- hyprshell util/share.sh file ;;
    trigger_share_folder) trigger_spawn_detached uwsm-app -- tui-terminal-exec --hypr-profile dialog --app-id org.tui.Share --title Share -- hyprshell util/share.sh folder ;;
    trigger_color_picker) hyprshell rofi/color-picker.sh ;;
    trigger_toggle_nightlight) hyprshell hyprsunset --toggle && pkill -u "${UID:-$(id -u)}" -SIGUSR2 -x waybar ;;
    trigger_toggle_keep_awake) hyprshell session/toggle-keep-awake.sh ;;
    trigger_toggle_waybar) hyprshell waybar/waybar.py --hide ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_trigger
