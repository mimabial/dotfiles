#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

trigger_rofi_gone() {
  ! hypr_layer_mapped rofi
}

trigger_spawn_detached() {
  (
    pkill -u "${UID}" -x rofi >/dev/null 2>&1 && hypr_wait_for 3 'closelayer>>rofi' trigger_rofi_gone
    exec "$@"
  ) >/dev/null 2>&1 </dev/null &
}

menu_register_domain_trigger() {
  local name="" icon="" label=""

  menu_define trigger_insert "Insert"
  menu_add_item trigger_insert "  Emoji" action trigger_insert_emoji
  menu_add_item trigger_insert "  Glyph" action trigger_insert_glyph
  menu_add_item trigger_insert "  Box Drawing" action trigger_insert_boxdraw

  menu_define trigger_capture "Capture"
  menu_add_item trigger_capture "  Screenshot" submenu trigger_screenshot
  menu_add_item trigger_capture "  Screenrecord" submenu trigger_screenrecord
  menu_add_item trigger_capture "  Color Picker" action trigger_color_picker
  menu_add_item trigger_capture "󰐲  QR Code" action trigger_capture_qr

  menu_define trigger_screenshot "Screenshot"
  menu_add_item trigger_screenshot "󰏫  Smart with Editing" action trigger_screenshot_edit
  menu_add_item trigger_screenshot "󰅇  Smart to Clipboard" action trigger_screenshot_clipboard
  menu_add_item trigger_screenshot "󰆓  Smart Save" action trigger_screenshot_save
  menu_add_item trigger_screenshot "󱂬  Window" action trigger_screenshot_window
  menu_add_item trigger_screenshot "󰍹  Focused Monitor" action trigger_screenshot_monitor
  menu_add_item trigger_screenshot "󰹑  All Outputs" action trigger_screenshot_all
  menu_add_item trigger_screenshot "󱉶  OCR Area" action trigger_screenshot_ocr

  menu_define trigger_screenrecord "Screenrecord"
  menu_add_item trigger_screenrecord "󱂬  Window" submenu trigger_screenrecord_window
  menu_add_item trigger_screenrecord "󰆞  Region" submenu trigger_screenrecord_region
  menu_add_item trigger_screenrecord "󰍹  Display" submenu trigger_screenrecord_display

  menu_define trigger_screenrecord_window "Audio"
  menu_add_item trigger_screenrecord_window "󰖁  No Audio" action trigger_screenrecord_window
  menu_add_item trigger_screenrecord_window "󰕾  With Audio" action trigger_screenrecord_window_audio

  menu_define trigger_screenrecord_region "Audio"
  menu_add_item trigger_screenrecord_region "󰖁  No Audio" action trigger_screenrecord_region
  menu_add_item trigger_screenrecord_region "󰕾  With Audio" action trigger_screenrecord_region_audio

  menu_define trigger_screenrecord_display "Audio"
  menu_add_item trigger_screenrecord_display "󰖁  No Audio" action trigger_screenrecord_display
  menu_add_item trigger_screenrecord_display "󰕾  With Audio" action trigger_screenrecord_display_audio

  menu_define trigger_toggle "Toggle"
  menu_add_item trigger_toggle "󰔎  Nightlight" action trigger_toggle_nightlight
  menu_add_item trigger_toggle "󱫖  Keep Awake" action trigger_toggle_keep_awake
  menu_add_item trigger_toggle "󰹬  Notifications" action trigger_toggle_notifications
  menu_add_item trigger_toggle "󰍜  Menu Bar" action trigger_toggle_bar
  menu_add_item trigger_toggle "󱂬  Workspace Layout" submenu trigger_toggle_workspace_layout
  menu_add_item trigger_toggle "󰊥  Window Gaps" action trigger_toggle_window_gaps

  menu_define trigger_toggle_workspace_layout "Workspace Layout" choice
  while IFS=$'\t' read -r name icon label; do
    menu_add_item trigger_toggle_workspace_layout "${icon}  ${label}" action "trigger_toggle_workspace_layout_${name}"
  done < <("${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/util/window-layout.sh" --list)
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
    trigger_color_picker) hyprshell rofi/color-picker.sh ;;
    trigger_capture_qr) trigger_spawn_detached hyprshell capture/qr.sh ;;
    trigger_insert_emoji) hyprshell rofi/run-after-close.sh -- hyprshell rofi/emoji-picker.sh ;;
    trigger_insert_glyph) hyprshell rofi/run-after-close.sh -- hyprshell rofi/glyph-picker.sh ;;
    trigger_insert_boxdraw) hyprshell rofi/run-after-close.sh -- hyprshell rofi/boxdraw-picker.sh ;;
    trigger_toggle_nightlight) hyprshell hyprsunset --toggle ;;
    trigger_toggle_keep_awake) hyprshell session/toggle-keep-awake.sh ;;
    trigger_toggle_notifications) hyprshell notify/notifications --toggle ;;
    trigger_toggle_bar) hyprshell quickshell/visibility.sh toggle ;;
    trigger_toggle_workspace_layout_*) hyprshell util/window-layout --set "${action_id#trigger_toggle_workspace_layout_}" ;;
    trigger_toggle_window_gaps) hyprshell window/gaps-toggle.sh ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_trigger

trigger_workspace_layout() {
  local lua="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/window-layout.lua" pattern='layout = "([^"]+)'

  [[ -r "${lua}" && "$(<"${lua}")" =~ ${pattern} ]] && printf '%s' "${BASH_REMATCH[1]}"
}

menu_active_trigger() {
  local target="$1" gaps_on='"css": *"[1-9]'

  case "${target}" in
    trigger_toggle_nightlight) menu_state HYPRSUNSET_ENABLED state_get HYPRSUNSET_ENABLED 0 && [[ "${REPLY}" == 1 ]] ;;
    trigger_toggle_keep_awake) menu_state HYPR_KEEP_AWAKE state_get HYPR_KEEP_AWAKE 0 && [[ "${REPLY}" == 1 ]] ;;
    trigger_toggle_notifications) menu_state notifications_paused dunstctl is-paused && [[ "${REPLY}" == false ]] ;;
    trigger_toggle_window_gaps) menu_state gaps_out hyprctl -j getoption general:gaps_out && [[ "${REPLY}" =~ ${gaps_on} ]] ;;
    trigger_toggle_workspace_layout_*) menu_choice "${target}" trigger_toggle_workspace_layout_ trigger_workspace_layout ;;
    *) return 1 ;;
  esac
}

menu_register_active_check menu_active_trigger
