#!/usr/bin/env bash

menu_register_domain_system() {
  menu_define remove "Remove"
  menu_add_item remove "󰣇  Package" action remove_package
  menu_add_item remove "  Font" action remove_font

  menu_define update "Update"
  menu_add_item update "  Config" submenu update_config
  menu_add_item update "  Process" submenu update_process
  menu_add_item update "󰇅  Hardware" submenu update_hardware
  menu_add_item update "  Firmware" action update_firmware
  menu_add_item update "  Password" submenu update_password
  menu_add_item update "  Timezone" action update_timezone
  menu_add_item update "  Time" action update_time

  menu_define update_process "Restart"
  menu_add_item update_process "  Hypridle" action update_process_hypridle
  menu_add_item update_process "  Hyprsunset" action update_process_hyprsunset
  menu_add_item update_process "󰍜  Waybar" action update_process_waybar
  menu_add_item update_process "󰀻  Rofi" action update_process_rofi

  menu_define update_config "Restore stock config"
  menu_add_item update_config "  Hyprland" action update_config_hyprland
  menu_add_item update_config "  Hypridle" action update_config_hypridle
  menu_add_item update_config "  Hyprlock" action update_config_hyprlock
  menu_add_item update_config "󰍜  Waybar" action update_config_waybar
  menu_add_item update_config "󰀻  Rofi" action update_config_rofi

  menu_define update_hardware "Restart"
  menu_add_item update_hardware "  Audio" action update_hardware_audio
  menu_add_item update_hardware "󱚾  Wi-Fi" action update_hardware_wifi
  menu_add_item update_hardware "󰂯  Bluetooth" action update_hardware_bluetooth

  menu_define update_password "Update Password"
  menu_add_item update_password "  Drive Encryption" action update_password_drive
  menu_add_item update_password "  User" action update_password_user

  menu_define system "System"
  menu_add_item system "  Lock" action system_lock
  menu_add_item system "󰤄  Suspend" action system_suspend
  menu_add_item system "󰜉  Restart" action system_restart
  menu_add_item system "󰐥  Shutdown" action system_shutdown
}

menu_run_action_system() {
  local action_id="$1"

  case "${action_id}" in
    remove_package) terminal hyprshell pkg/remove.sh ;;
    update_firmware) present_terminal hyprshell system/firmware.sh ;;
    update_timezone) present_terminal hyprshell system/timezone.sh ;;
    update_time) present_terminal hyprshell system/time.sh ;;
    update_process_hypridle) hyprshell service/restart.sh hypridle ;;
    update_process_hyprsunset) hyprshell service/restart.sh hyprsunset ;;
    update_process_waybar) hyprshell waybar.py --restart-direct ;;
    update_process_rofi) pkill -x rofi >/dev/null 2>&1 || true ;;
    update_config_hyprland) present_terminal hyprshell service/domain.sh restore hypr-config ;;
    update_config_hypridle) present_terminal hyprshell service/domain.sh restore hypridle ;;
    update_config_hyprlock) present_terminal hyprshell service/domain.sh restore hyprlock ;;
    update_config_waybar) present_terminal hyprshell service/domain.sh restore waybar ;;
    update_config_rofi) present_terminal hyprshell service/domain.sh restore rofi ;;
    update_hardware_audio) present_terminal hyprshell service/restart.sh pipewire ;;
    update_hardware_wifi) present_terminal hyprshell service/restart.sh wifi ;;
    update_hardware_bluetooth) present_terminal hyprshell service/restart.sh bluetooth ;;
    update_password_drive) present_terminal hyprshell drive-set-password.sh ;;
    update_password_user) present_terminal passwd ;;
    system_lock) hyprshell session/hyprlock.sh ;;
    system_suspend) systemctl suspend ;;
    system_restart) hyprshell cmd/powerctl.sh reboot ;;
    system_shutdown) hyprshell cmd/powerctl.sh shutdown ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_system
