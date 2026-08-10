#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

menu_register_domain_system() {
  menu_define remove "Remove"
  menu_add_item remove "󰣇  Package" action remove_package
  menu_add_item remove "  Font" action remove_font

  menu_define update "Maintenance"
  menu_add_item update "󰏗  Update system packages" action update_system
  menu_add_item update "  Restore stock configs" submenu update_config
  menu_add_item update "  Desktop processes" submenu update_process
  menu_add_item update "󰇅  Hardware recovery" submenu update_hardware
  menu_add_item update "  Update firmware" action update_firmware
  menu_add_item update "  Change passwords" submenu update_password
  menu_add_item update "  Set timezone" action update_timezone
  menu_add_item update "  Resync system clock" action update_time

  menu_define update_process "Desktop processes"
  menu_add_item update_process "  Restart Hypridle" action update_process_hypridle
  menu_add_item update_process "  Restart Hyprsunset" action update_process_hyprsunset
  menu_add_item update_process "󰍜  Restart Waybar" action update_process_waybar
  menu_add_item update_process "󰀻  Close Rofi instances" action update_process_rofi

  menu_define update_config "Restore stock config"
  menu_add_item update_config "  Restore stock Hyprland config" action update_config_hyprland
  menu_add_item update_config "  Restore stock Hypridle config" action update_config_hypridle
  menu_add_item update_config "  Restore stock Hyprlock config" action update_config_hyprlock
  menu_add_item update_config "󰍜  Restore stock Waybar config" action update_config_waybar
  menu_add_item update_config "󰀻  Restore stock Rofi config" action update_config_rofi

  menu_define update_hardware "Hardware recovery"
  menu_add_item update_hardware "  Restart audio service" action update_hardware_audio
  menu_add_item update_hardware "󱚾  Unblock Wi-Fi radio" action update_hardware_wifi
  menu_add_item update_hardware "󰂯  Unblock Bluetooth radio" action update_hardware_bluetooth

  menu_define update_password "Change password"
  menu_add_item update_password "  Change drive encryption password" action update_password_drive
  menu_add_item update_password "  Change user password" action update_password_user

  menu_define system "System"
  menu_add_item system "  Lock" action system_lock
  menu_add_item system "󰤄  Suspend" action system_suspend
  menu_add_item system "󰜉  Restart" action system_restart
  menu_add_item system "󰐥  Shutdown" action system_shutdown
}

menu_run_action_system() {
  local action_id="$1"

  case "${action_id}" in
    remove_package) terminal hyprshell pm --noconfirm remove ;;
    update_system) hyprshell system/system.update.sh up ;;
    update_firmware) present_terminal hyprshell system/firmware.sh ;;
    update_timezone) present_terminal hyprshell system/timezone.sh ;;
    update_time) present_terminal hyprshell system/time.sh ;;
    update_process_hypridle) hyprshell service/restart.sh hypridle ;;
    update_process_hyprsunset) hyprshell service/restart.sh hyprsunset ;;
    update_process_waybar) hyprshell waybar.py --restart-direct ;;
    update_process_rofi) pkill -u "${UID:-$(id -u)}" -x rofi >/dev/null 2>&1 || true ;;
    update_config_hyprland) present_terminal hyprshell service/domain.sh restore hypr-config ;;
    update_config_hypridle) present_terminal hyprshell service/domain.sh restore hypridle ;;
    update_config_hyprlock) present_terminal hyprshell service/domain.sh restore hyprlock ;;
    update_config_waybar) present_terminal hyprshell service/domain.sh restore waybar ;;
    update_config_rofi) present_terminal hyprshell service/domain.sh restore rofi ;;
    update_hardware_audio) present_terminal hyprshell service/restart.sh pipewire ;;
    update_hardware_wifi) present_terminal hyprshell service/restart.sh wifi ;;
    update_hardware_bluetooth) present_terminal hyprshell service/restart.sh bluetooth ;;
    update_password_drive) present_terminal hyprshell system/drive-password.sh ;;
    update_password_user) present_terminal passwd ;;
    system_lock) hyprshell session/hyprlock.sh ;;
    system_suspend) hyprshell session/suspend.sh ;;
    system_restart) hyprshell system/powerctl.sh reboot ;;
    system_shutdown) hyprshell system/powerctl.sh shutdown ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_system
