#!/usr/bin/env bash

menu_register_domain_setup() {
  menu_define setup "Setup"
  menu_add_item setup "  Audio" action setup_audio
  menu_add_item setup "  Wifi" action setup_wifi
  menu_add_item setup "  Bluetooth" action setup_bluetooth
  menu_add_item setup "󱫋  Network" action setup_network
  menu_add_item setup "  Power Profile" action setup_power_profile
  menu_add_item setup "󰍹  Monitors" action setup_monitors

  [[ -f ~/.config/hypr/keybindings.conf ]] && menu_add_item setup "  Keybindings" action setup_keybindings
  [[ -f ~/.config/hypr/input.conf ]] && menu_add_item setup "  Input" action setup_input
}

menu_run_action_setup() {
  local action_id="$1"

  case "${action_id}" in
    setup_audio) present_terminal --app-id org.tui.Wiremix --title Wiremix -- wiremix ;;
    setup_wifi) rfkill unblock wifi && hyprshell launch/wifi.sh ;;
    setup_bluetooth) rfkill unblock bluetooth && present_terminal --app-id org.tui.Bluetui --title Bluetui -- bluetui ;;
    setup_network) present_terminal --app-id org.tui.Oryx --title Oryx -- sudo oryx ;;
    setup_monitors) open_in_editor ~/.config/hypr/monitors.conf ;;
    setup_keybindings) open_in_editor ~/.config/hypr/keybindings.conf ;;
    setup_input) open_in_editor ~/.config/hypr/input.conf ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_setup
