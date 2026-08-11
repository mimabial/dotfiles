#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

menu_register_domain_gaming() {
  menu_define gaming "Gaming"
  menu_add_item gaming "  Game Launcher" action gaming_launcher
  menu_add_item gaming "  Steam Games" action gaming_launcher_steam
  menu_add_item gaming "󰺵  Lutris Games" action gaming_launcher_lutris
  menu_add_item gaming "  Steam" action gaming_steam
  menu_add_item gaming "󰺵  Lutris" action gaming_lutris
  menu_add_item gaming "󰹑  MangoHud Config" action gaming_mangohud_config
  menu_add_item gaming "  GameMode Status" action gaming_gamemode_status
  menu_add_item gaming "󰜺  Stop Lutris Wine" action gaming_wine_stop
}

menu_run_action_gaming() {
  local action_id="$1"

  case "${action_id}" in
    gaming_launcher) hyprshell gaming/launcher.sh ;;
    gaming_launcher_steam) hyprshell gaming/launcher.sh --backend steam ;;
    gaming_launcher_lutris) hyprshell gaming/launcher.sh --backend lutris ;;
    gaming_steam) uwsm-app -- steam ;;
    gaming_lutris) uwsm-app -- lutris ;;
    gaming_mangohud_config) open_in_editor ~/.config/MangoHud/MangoHud.conf ;;
    gaming_wine_stop) hyprshell gaming/wine-stop.sh ;;
    gaming_gamemode_status)
      present_terminal --hypr-profile tui --app-id org.tui.GameMode --title GameMode -- bash -lc 'printf "GameMode status:\n"; gamemoded -s || true; printf "\nClients:\n"; gamemodelist || true'
      ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_gaming
