#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

menu_register_domain_setup() {
  menu_define setup "Setup"
  menu_add_item setup "  Audio" action setup_audio
  menu_add_item setup "  Wifi" action setup_wifi
  menu_add_item setup "  Bluetooth" action setup_bluetooth
  menu_add_item setup "󱫋  Network" action setup_network
  menu_add_item setup "  Power Profile" action setup_power_profile
  menu_add_item setup "󰍹  Monitors" action setup_monitors

  [[ -f ~/.config/hypr/keybindings.lua ]] && menu_add_item setup "  Keybindings" action setup_keybindings
}

menu_run_action_setup() {
  local action_id="$1"

  case "${action_id}" in
    setup_audio) present_terminal --hypr-profile tui --app-id org.tui.Wiremix --title Wiremix -- wiremix ;;
    setup_wifi) rfkill unblock wifi && present_terminal --hypr-profile tui --app-id org.tui.Impala --title Impala -- impala ;;
    setup_bluetooth) rfkill unblock bluetooth && present_terminal --hypr-profile tui --app-id org.tui.Bluetui --title Bluetui -- bluetui ;;
    setup_network) present_terminal --hypr-profile tui --app-id org.tui.Oryx --title Oryx -- sudo oryx ;;
    setup_monitors) open_in_editor ~/.config/hypr/monitors.lua ;;
    setup_keybindings) open_in_editor ~/.config/hypr/keybindings.lua ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_setup
