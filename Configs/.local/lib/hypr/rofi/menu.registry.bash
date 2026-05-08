#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

HYPR_MENU_REGISTERED="${HYPR_MENU_REGISTERED:-0}"

menu_register_all() {
  [[ "${HYPR_MENU_REGISTERED}" -eq 0 ]] || return 0

  menu_define main "Main"
  menu_add_item main "󱡴  Search All" action search_all 0
  menu_add_item main "  Tools" submenu dev_tools
  menu_add_item main "󰀻  Apps" action main_apps 0
  menu_add_item main "  Learn" submenu learn
  menu_add_item main "󱊨  Trigger" submenu trigger
  menu_add_item main "󰢵  Style" submenu style
  menu_add_item main "  Setup" submenu setup
  menu_add_item main "󰉉  Install" submenu install
  menu_add_item main "󰭌  Remove" submenu remove
  menu_add_item main "  Update" submenu update
  menu_add_item main "  System" submenu system

  menu_register_domain_core
  menu_register_domain_trigger
  menu_register_domain_style
  menu_register_domain_setup
  menu_register_domain_install
  menu_register_domain_system

  HYPR_MENU_REGISTERED=1
}

show_main_menu() {
  menu_show_menu main
}

menu_open_argument() {
  local arg="${1:-}"
  local normalized="${arg,,}"

  case "${arg}" in
    --menu-id)
      menu_show_menu "${2:-main}"
      ;;
    --search-all)
      show_search_all_menu
      ;;
    *)
      case "${normalized}" in
        *search*) show_search_all_menu ;;
        *tools*) menu_show_menu dev_tools ;;
        *apps*) menu_run_action main_apps ;;
        *learn*) menu_show_menu learn ;;
        *trigger*) menu_show_menu trigger ;;
        *style*) menu_show_menu style ;;
        *theme*) menu_run_action style_theme ;;
        *wallpaper*) menu_run_action style_wallpaper ;;
        *setup*) menu_show_menu setup ;;
        *power*) menu_run_action setup_power_profile ;;
        *install*) menu_show_menu install ;;
        *remove*) menu_show_menu remove ;;
        *update*) menu_show_menu update ;;
        *system*) menu_show_menu system ;;
        *) menu_show_menu main ;;
      esac
      ;;
  esac
}
