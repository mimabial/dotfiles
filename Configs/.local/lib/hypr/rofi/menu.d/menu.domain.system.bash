#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

remove_gaming_package() {
  local name="$1"
  local package="$2"

  if ! pacman -Q "${package}" >/dev/null 2>&1; then
    dunstify -i dialog-information "${name} is not installed"
    return 0
  fi
  present_terminal hyprshell pm --noconfirm remove "${package}"
}

menu_register_domain_system() {
  menu_define remove "Remove"
  menu_add_item remove "󰣇  Package" action remove_package
  menu_add_item remove "  Font" action remove_font
  menu_add_item remove "  Web App" action remove_webapp
  menu_add_item remove "  TUI" action remove_tui
  menu_add_item remove "  Gaming" submenu remove_gaming
  menu_add_item remove "󰍲  Windows VM" action remove_windows

  menu_define remove_gaming "Remove"
  menu_add_item remove_gaming "  Lutris" action remove_gaming_lutris
  menu_add_item remove_gaming "󱓟  Heroic (Epic Games)" action remove_gaming_heroic
  menu_add_item remove_gaming "󰯉  RetroArch Game Launcher" action remove_gaming_retro_launcher

  menu_define update "Maintenance"
  menu_add_item update "󰏗  Update system packages" action update_system
  menu_add_item update "  Desktop processes" submenu update_process
  menu_add_item update "󰇅  Hardware recovery" submenu update_hardware
  menu_add_item update "  Update firmware" action update_firmware
  menu_add_item update "  Change passwords" submenu update_password
  menu_add_item update "  Set timezone" action update_timezone
  menu_add_item update "  Resync system clock" action update_time
  menu_add_item update "󰚰  Refresh managed files" action update_managed_refresh
  menu_add_item update "󰆼  Rebuild picker databases" action update_picker_db
  menu_add_item update "󰋊  Rebuild wallpaper cache" action update_wallpaper_cache
  menu_add_item update "󰛖  Audit unused fonts" action update_fonts_unused
  menu_add_item update "󰃤  Collect debug log" action update_debug_log

  menu_define update_process "Desktop processes"
  menu_add_item update_process "  Restart Hypridle" action update_process_hypridle
  menu_add_item update_process "  Restart Hyprsunset" action update_process_hyprsunset
  menu_add_item update_process "󰍜  Reload Quickshell" action update_process_quickshell
  menu_add_item update_process "󰀻  Close Rofi instances" action update_process_rofi
  menu_add_item update_process "󰒓  Restart desktop portals" action update_process_portals

  menu_define update_hardware "Hardware recovery"
  menu_add_item update_hardware "  Restart audio service" action update_hardware_audio
  menu_add_item update_hardware "󱚾  Unblock Wi-Fi radio" action update_hardware_wifi
  menu_add_item update_hardware "󰂯  Unblock Bluetooth radio" action update_hardware_bluetooth
  menu_add_item update_hardware "󰋊  Repair NTFS mount" action update_hardware_ntfs

  menu_define update_password "Change password"
  menu_add_item update_password "  Change drive encryption password" action update_password_drive
  menu_add_item update_password "  Change user password" action update_password_user

  menu_define system "System"
  menu_add_item system "󱂬  Window Sessions" submenu system_session
  menu_add_item system "  Lock" action system_lock
  menu_add_item system "󰤄  Suspend" action system_suspend
  menu_add_item system "󰍃  Logout" action system_logout
  menu_add_item system "󰜉  Restart" action system_restart
  menu_add_item system "󰐥  Shutdown" action system_shutdown

  menu_define system_session "Window Sessions"
  menu_add_item system_session "󰆓  Save Session" action system_session_save
  menu_add_item system_session "󰚰  Restore Session" action system_session_restore
  menu_add_item system_session "󰩹  Delete Session" action system_session_delete
  menu_add_item system_session "󰋼  List Sessions" action system_session_list
}

menu_run_action_system() {
  local action_id="$1"

  case "${action_id}" in
    remove_package) terminal hyprshell pm --noconfirm remove ;;
    remove_webapp) present_terminal hyprshell install/webapp-remove.sh ;;
    remove_tui) present_terminal hyprshell install/tui-remove.sh ;;
    remove_gaming_lutris) remove_gaming_package Lutris lutris ;;
    remove_gaming_heroic) remove_gaming_package "Heroic Games Launcher" heroic-games-launcher-bin ;;
    remove_gaming_retro_launcher) hyprshell gaming/retro-launcher.sh --remove ;;
    remove_windows) present_terminal hyprshell vm/windows.sh remove ;;
    update_system) hyprshell system/system.update.sh up ;;
    update_firmware) present_terminal hyprshell system/firmware.sh ;;
    update_timezone) present_terminal hyprshell system/timezone.sh ;;
    update_time) present_terminal hyprshell system/time.sh ;;
    update_process_hypridle) hyprshell service/restart.sh hypridle ;;
    update_process_hyprsunset) hyprshell service/restart.sh hyprsunset ;;
    update_process_quickshell) quickshell ipc call bar reload ;;
    update_managed_refresh) present_terminal hyprshell service/managed.sh --mode refresh hypr-config hypr-state hyprlock hypridle rofi ;;
    update_picker_db) present_terminal hyprshell rofi/picker-db-generate.py --boxdraw --glyph ;;
    update_wallpaper_cache) present_terminal hyprshell wallpaper/wallpaper.cache.sh -f ;;
    update_fonts_unused) present_terminal hyprshell fonts/find-unused.sh ;;
    update_debug_log) present_terminal hyprshell util/debug.hypr.sh ;;
    update_process_rofi) pkill -u "${UID:-$(id -u)}" -x rofi >/dev/null 2>&1 || true ;;
    update_process_portals) present_terminal hyprshell system/reset-xdg-portal.sh ;;
    update_hardware_audio) present_terminal hyprshell service/restart.sh pipewire ;;
    update_hardware_wifi) present_terminal hyprshell service/restart.sh wifi ;;
    update_hardware_bluetooth) present_terminal hyprshell service/restart.sh bluetooth ;;
    update_hardware_ntfs) present_terminal hyprshell system/ntfs-repair-mount.sh ;;
    update_password_drive) present_terminal hyprshell system/drive-password.sh ;;
    update_password_user) present_terminal passwd ;;
    system_session_save) present_terminal hyprshell session/snapshot.py save ;;
    system_session_list) present_terminal hyprshell session/snapshot.py list ;;
    system_lock) hyprshell session/hyprlock.sh ;;
    system_suspend) hyprshell session/suspend.sh ;;
    system_logout) hyprshell rofi/run-after-close.sh -- hyprshell session/logout-launch.sh ;;
    system_restart) hyprshell system/powerctl.sh reboot ;;
    system_shutdown) hyprshell system/powerctl.sh shutdown ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_system
