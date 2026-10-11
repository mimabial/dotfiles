#!/usr/bin/env bash

setup_pick_input_language() {
  local layouts="" selection="" layout="" variant=""

  layouts="$(xkbcli list | awk -F"'" '/^option_groups:/ { exit } /^- layout:/ { layout = $2 } /^  variant:/ { variant = $2 }
    layout && /^  description:/ { sub(/^  description: /, ""); print $0 "\t" layout "\t" variant }')"
  selection="$(menu "Input Language" "$(cut -f1 <<<"${layouts}")" --select "$(hyprctl -j devices | jq -r '.keyboards[] | select(.main).active_keymap')")"
  [[ -n "${selection}" ]] || menu_exit_or_show setup_language
  IFS=$'\t' read -r _ layout variant < <(awk -F'\t' -v description="${selection}" '$1 == description { print; exit }' <<<"${layouts}")
  hyprshell util/keyboard-layout --select "${layout}" "${variant}" >/dev/null
}

setup_register_power_profiles() {
  local profile="" profile_label=""
  local -A profile_icons=([power-saver]="󰌪" [balanced]="󰗑" [performance]="󱐋")

  menu_define setup_power_profile "Power Profile" choice
  for profile in $("${HYPR_LIB_DIR}/system/powerprofiles.sh"); do
    profile_label="${profile//-/ }"
    menu_add_item setup_power_profile "${profile_icons[${profile}]:-}  ${profile_label^}" action "setup_power_profile_${profile}"
  done
}

setup_register_monitors() {
  local scale=""

  menu_define setup_monitors "Monitors"
  menu_add_item setup_monitors "󱇧  Edit Config" action setup_monitors_config
  menu_add_item setup_monitors "󰩨  Set Scale" submenu setup_monitor_scale
  menu_add_item setup_monitors "󰌢  Toggle Laptop Display" action setup_monitor_laptop_toggle
  menu_add_item setup_monitors "󰍺  Toggle Mirroring" action setup_monitor_mirror_toggle

  menu_define setup_monitor_scale "Scale" choice
  for scale in $(bash "${HYPR_LIB_DIR}/system/monitor-scale.sh" --list); do
    menu_add_item setup_monitor_scale "󰍹  ${scale}x" action "setup_monitor_scale_${scale}"
  done
}

setup_register_defaults() {
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/setup/default-apps/applications.bash"
  local record="" role="" selection="" command="" name="" icon=""
  local -A current=([agent]="${HYPR_DEFAULT_AGENT:-}" [browser]="${BROWSER:-}" [terminal]="${TERMINAL:-}" [editor]="${EDITOR:-}")

  menu_define setup_default "Defaults"
  menu_add_item setup_default "󰚩  Agent" submenu setup_default_agent
  menu_add_item setup_default "  Browser" submenu setup_default_browser
  menu_add_item setup_default "  Terminal" submenu setup_default_terminal
  menu_add_item setup_default "  Editor" submenu setup_default_editor
  menu_define setup_default_agent "Default Agent" choice
  menu_define setup_default_browser "Default Browser" choice
  menu_define setup_default_terminal "Default Terminal" choice
  menu_define setup_default_editor "Default Editor" choice

  for record in "${DEFAULT_APP_CATALOG[@]}"; do
    IFS='|' read -r role selection command _ name icon <<<"${record}"
    command -v "${command}" >/dev/null 2>&1 || continue
    [[ "${current[${role}]##*/}" == "${command}" ]] && menu_mark_active "setup_default_${role}_${selection}"
    menu_add_item "setup_default_${role}" "${icon}  ${name}" action "setup_default_${role}_${selection}"
  done
}

menu_register_domain_setup() {
  menu_define setup "Setup"
  menu_add_item setup "  Defaults" submenu setup_default
  menu_add_item setup "󰗊  Language" submenu setup_language
  menu_add_item setup "  Audio" action setup_audio
  menu_add_item setup "  Wifi" action setup_wifi
  menu_add_item setup "  Bluetooth" action setup_bluetooth
  menu_add_item setup "󱫋  Network" action setup_network
  menu_add_item setup "󰇖  DNS" action setup_dns
  menu_add_item setup "󰐲  Wi-Fi QR Code" action setup_wifi_qr
  menu_add_item setup "  Power Profile" submenu setup_power_profile
  menu_add_item setup "󰍹  Monitors" submenu setup_monitors
  menu_add_item setup "  Security" submenu setup_security

  setup_register_power_profiles
  setup_register_monitors

  menu_define setup_language "Language"
  menu_add_item setup_language "󰇧  System" action setup_language_system
  menu_add_item setup_language "󰀄  Display" action setup_language_display
  menu_add_item setup_language "󰌌  Input" action setup_language_input

  setup_register_defaults

  menu_define setup_security "Security"
  menu_add_item setup_security "󰈷  Fingerprint" action setup_security_fingerprint
  menu_add_item setup_security "  Fido2" action setup_security_fido2
  menu_add_item setup_security "󰣀  SSHD" action setup_security_sshd
  menu_add_item setup_security "󰟵  Passwordless Sudo" action setup_security_passwordless_sudo
  menu_add_item setup_security "󰡨  Sudoless Docker" action setup_security_sudoless_docker

  [[ -f "${HYPR_CONFIG_HOME}/keybindings.lua" ]] && menu_add_item setup "  Keybindings" action setup_keybindings
}

menu_run_action_setup() {
  local action_id="$1"

  case "${action_id}" in
    setup_language_system) menu_pick_language system setup_language ;;
    setup_language_display) menu_pick_language display setup_language ;;
    setup_language_input) setup_pick_input_language ;;
    setup_default_agent_*) hyprshell setup/default-app.sh agent "${action_id#setup_default_agent_}" ;;
    setup_default_browser_*) hyprshell setup/default-app.sh browser "${action_id#setup_default_browser_}" ;;
    setup_default_terminal_*) hyprshell setup/default-app.sh terminal "${action_id#setup_default_terminal_}" ;;
    setup_default_editor_*) hyprshell setup/default-app.sh editor "${action_id#setup_default_editor_}" ;;
    setup_power_profile_*) hyprshell system/powerprofiles.sh --set "${action_id#setup_power_profile_}" ;;
    setup_audio) menu_present_terminal --hypr-profile tui --app-id org.tui.Wiremix --title Wiremix -- wiremix ;;
    setup_wifi) rfkill unblock wifi && menu_present_terminal --hypr-profile tui --app-id org.tui.Impala --title Impala -- impala ;;
    setup_bluetooth) hyprshell launch/bluetooth ;;
    setup_network) menu_present_terminal --hypr-profile tui --app-id org.tui.Oryx --title Oryx -- sudo oryx ;;
    setup_monitors_config) menu_edit_config "${HYPR_CONFIG_HOME}/monitors.lua" ;;
    setup_monitor_scale_*) hyprshell system/monitor-scale.sh "${action_id#setup_monitor_scale_}" ;;
    setup_monitor_laptop_toggle) hyprshell system/monitor-internal.sh toggle ;;
    setup_monitor_mirror_toggle) hyprshell system/monitor-mirror.sh toggle ;;
    setup_keybindings) menu_edit_config "${HYPR_CONFIG_HOME}/keybindings.lua" ;;
    setup_dns) menu_present_terminal hyprshell install/dns.sh ;;
    setup_wifi_qr) menu_present_terminal --app-id org.tui.WifiQr --title "Wi-Fi QR" -- hyprshell util/wifi-pass.sh --qr ;;
    setup_security_fingerprint) menu_present_terminal hyprshell install/fingerprint.sh ;;
    setup_security_fido2) menu_present_terminal hyprshell install/fido2.sh ;;
    setup_security_sshd) menu_present_terminal hyprshell install/sshd.sh ;;
    setup_security_passwordless_sudo) menu_present_terminal hyprshell install/passwordless-sudo.sh ;;
    setup_security_sudoless_docker) menu_present_terminal hyprshell install/sudoless-docker.sh ;;
    *) return "${MENU_ACTION_UNKNOWN}" ;;
  esac
}

menu_register_action_handler menu_run_action_setup

setup_focused_monitor_scale() {
  rofi_monitors_json | jq -r '[.[] | select(.focused)][0].scale * 100 | round / 100'
}

menu_active_setup() {
  case "$1" in
    setup_power_profile_*) menu_choice_matches "$1" setup_power_profile_ hypr_power_profile ;;
    setup_monitor_scale_*) menu_choice_matches "$1" setup_monitor_scale_ setup_focused_monitor_scale ;;
    *) return 1 ;;
  esac
}

menu_register_active_check menu_active_setup
