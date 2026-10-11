#!/usr/bin/env bash

system_pick_font_to_remove() {
  source "${BASH_SOURCE[0]%/*}/../menu/font-packages.bash"
  local mode="${1:-all}"
  local unused_option="  Unused"
  local prompt="Remove Font"
  local empty_label="No installed Nerd Fonts"
  local selection=""
  local package=""
  local -a font_labels=()
  local -A font_packages=()

  case "${mode}" in
    unused)
      prompt="Remove Unused Font"
      empty_label="No unused Nerd Fonts"
      nerd_font_menu_build unused font_labels font_packages
      ;;
    *)
      nerd_font_menu_build installed font_labels font_packages
      ;;
  esac

  if [[ "${#font_labels[@]}" -gt 0 ]]; then
    if [[ "${mode}" == "unused" ]]; then
      selection="$(menu "${prompt}" "$(printf '%s\n' "${font_labels[@]}")")"
    else
      selection="$(menu "${prompt}" "${unused_option}"$'\n'"$(printf '%s\n' "${font_labels[@]}")")"
    fi
  else
    if [[ "${mode}" == "unused" ]]; then
      selection="$(menu "${prompt}" "${empty_label}")"
    else
      selection="$(menu "${prompt}" "${unused_option}"$'\n'"${empty_label}" --select "${unused_option}")"
    fi
  fi

  case "${selection}" in
    "${unused_option}")
      system_pick_font_to_remove unused
      ;;
    "${empty_label}" | "")
      menu_exit_or_show remove
      ;;
    *)
      package="${font_packages["${selection}"]:-}"
      [[ -n "${package}" ]] || {
        system_pick_font_to_remove
        return 0
      }
      menu_present_terminal --hypr-profile dialog --app-id org.font.Remove --title "Remove ${selection}" -- hyprshell fonts/font-nerd-remove.sh --packages "${package}"
      ;;
  esac
}

system_pick_session_snapshot() {
  local mode="${1:-restore}"
  local empty_label="No saved sessions"
  local prompt="Restore Session"
  local names=""
  local selection=""

  [[ "${mode}" == "delete" ]] && prompt="Delete Session"

  names="$(hyprshell session/snapshot.py list 2>/dev/null)"
  [[ "${names}" == "no saved sessions" ]] && names=""

  if [[ -n "${names}" ]]; then
    selection="$(menu "${prompt}" "${names}")"
  else
    selection="$(menu "${prompt}" "${empty_label}")"
  fi

  case "${selection}" in
    "${empty_label}" | "")
      menu_exit_or_show system_session
      ;;
    *)
      menu_present_terminal hyprshell session/snapshot.py "${mode}" "${selection}"
      ;;
  esac
}

remove_gaming_package() {
  local name="$1"
  local package="$2"

  if ! pacman -Q "${package}" >/dev/null 2>&1; then
    dunstify -i dialog-information "${name} is not installed"
    return 0
  fi
  menu_present_terminal hyprshell pm --noconfirm remove "${package}"
}

menu_register_domain_system() {
  menu_define remove "Remove"
  menu_add_item remove "󰏖  Package" action remove_package
  menu_add_item remove "  Font" action remove_font
  menu_add_item remove "󰗊  Language" action remove_language
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
  menu_add_item update_process "󰒲  Restart Hypridle" action update_process_hypridle
  menu_add_item update_process "󰖚  Restart Hyprsunset" action update_process_hyprsunset
  menu_add_item update_process "󰍜  Reload Quickshell" action update_process_quickshell
  menu_add_item update_process "󰀻  Close Rofi instances" action update_process_rofi
  menu_add_item update_process "󰒓  Restart desktop portals" action update_process_portals

  menu_define update_hardware "Hardware recovery"
  menu_add_item update_hardware "  Restart audio service" action update_hardware_audio
  menu_add_item update_hardware "󱚾  Unblock Wi-Fi radio" action update_hardware_wifi
  menu_add_item update_hardware "󰂯  Unblock Bluetooth radio" action update_hardware_bluetooth
  menu_add_item update_hardware "󰋊  Repair NTFS mount" action update_hardware_ntfs

  menu_define update_password "Change password"
  menu_add_item update_password "󰋊  Change drive encryption password" action update_password_drive
  menu_add_item update_password "󰀋  Change user password" action update_password_user

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
    remove_font) system_pick_font_to_remove ;;
    remove_language) menu_pick_language remove remove ;;
    system_session_restore) system_pick_session_snapshot restore ;;
    system_session_delete) system_pick_session_snapshot delete ;;
    remove_package) menu_launch_shell_terminal hyprshell pm --noconfirm remove ;;
    remove_webapp) menu_present_terminal hyprshell install/webapp-remove.sh ;;
    remove_tui) menu_present_terminal hyprshell install/tui-remove.sh ;;
    remove_gaming_lutris) remove_gaming_package Lutris lutris ;;
    remove_gaming_heroic) remove_gaming_package "Heroic Games Launcher" heroic-games-launcher-bin ;;
    remove_gaming_retro_launcher) hyprshell gaming/retro-launcher.sh remove ;;
    remove_windows) menu_present_terminal hyprshell vm/windows.sh remove ;;
    update_system) hyprshell system/system.update.sh up ;;
    update_firmware) menu_present_terminal hyprshell system/firmware.sh ;;
    update_timezone) menu_present_terminal hyprshell system/timezone.sh ;;
    update_time) menu_present_terminal hyprshell system/time.sh ;;
    update_process_hypridle) hyprshell service/recover.sh hypridle ;;
    update_process_hyprsunset) hyprshell service/recover.sh hyprsunset ;;
    update_process_quickshell) quickshell ipc call bar reload ;;
    update_managed_refresh) menu_present_terminal hyprshell service/apply-managed-domains.sh --mode refresh hypr-config hyprlock hypridle rofi ;;
    update_picker_db) menu_present_terminal hyprshell rofi/picker-db-generate.py --boxdraw --glyph ;;
    update_wallpaper_cache) menu_present_terminal hyprshell wallpaper/wallpaper.cache.sh -f ;;
    update_fonts_unused) menu_present_terminal hyprshell fonts/find-unused.sh ;;
    update_debug_log) menu_present_terminal hyprshell util/debug.hypr.sh ;;
    update_process_rofi) pkill -u "${UID}" -x rofi >/dev/null 2>&1 || true ;;
    update_process_portals) menu_present_terminal hyprshell system/reset-xdg-portal.sh ;;
    update_hardware_audio) menu_present_terminal hyprshell service/recover.sh pipewire ;;
    update_hardware_wifi) menu_present_terminal hyprshell service/recover.sh wifi ;;
    update_hardware_bluetooth) menu_present_terminal hyprshell service/recover.sh bluetooth ;;
    update_hardware_ntfs) menu_present_terminal hyprshell system/ntfs-repair-mount.sh ;;
    update_password_drive) menu_present_terminal hyprshell system/drive-password.sh ;;
    update_password_user) menu_present_terminal passwd ;;
    system_session_save) menu_present_terminal hyprshell session/snapshot.py save ;;
    system_session_list) menu_present_terminal hyprshell session/snapshot.py list ;;
    system_lock) hyprshell session/lock-screen.sh ;;
    system_suspend) hyprshell session/suspend.sh ;;
    system_logout) hyprshell rofi/run-after-close.sh -- hyprshell session/logout-launch.sh ;;
    system_restart) hyprshell system/powerctl.sh reboot ;;
    system_shutdown) hyprshell system/powerctl.sh shutdown ;;
    *) return "${MENU_ACTION_UNKNOWN}" ;;
  esac
}

menu_register_action_handler menu_run_action_system
