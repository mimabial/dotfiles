#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

setup_default_label() {
  local current="$1"
  local value="$2"
  local label="$3"

  [[ "${current}" == "${value}" ]] && printf '%s  ✓' "${label}" || printf '%s' "${label}"
}

setup_add_default_item() {
  local menu_id="$1"
  local current="$2"
  local value="$3"
  local label="$4"
  local action_id="$5"
  local command_name="$6"

  command -v "${command_name}" >/dev/null 2>&1 || return 0
  menu_add_item "${menu_id}" "$(setup_default_label "${current}" "${value}" "${label}")" action "${action_id}"
}

menu_register_domain_setup() {
  local default_agent=""
  local default_browser=""
  local default_editor=""
  local default_terminal=""

  default_agent="$(hyprshell setup/default.sh agent 2>/dev/null || true)"
  default_browser="$(hyprshell setup/default.sh browser 2>/dev/null || true)"
  default_terminal="$(hyprshell setup/default.sh terminal 2>/dev/null || true)"
  default_editor="$(hyprshell setup/default.sh editor 2>/dev/null || true)"

  menu_define setup "Setup"
  menu_add_item setup "  Defaults" submenu setup_default
  menu_add_item setup "  Audio" action setup_audio
  menu_add_item setup "  Wifi" action setup_wifi
  menu_add_item setup "  Bluetooth" action setup_bluetooth
  menu_add_item setup "󱫋  Network" action setup_network
  menu_add_item setup "󰇖  DNS" action setup_dns
  menu_add_item setup "󰐲  Wi-Fi QR Code" action setup_wifi_qr
  menu_add_item setup "  Power Profile" action setup_power_profile
  menu_add_item setup "󰍹  Monitors" submenu setup_monitors
  menu_add_item setup "  Security" submenu setup_security

  menu_define setup_monitors "Monitors"
  menu_add_item setup_monitors "󰍹  Edit Config" action setup_monitors_config
  menu_add_item setup_monitors "󰍹  Set Scale" action setup_monitor_scale
  menu_add_item setup_monitors "󰍹  Toggle Laptop Display" action setup_monitor_laptop_toggle
  menu_add_item setup_monitors "󰍹  Toggle Mirroring" action setup_monitor_mirror_toggle

  menu_define setup_default "Defaults"
  menu_add_item setup_default "󰚩  Agent" submenu setup_default_agent
  menu_add_item setup_default "  Browser" submenu setup_default_browser
  menu_add_item setup_default "  Terminal" submenu setup_default_terminal
  menu_add_item setup_default "  Editor" submenu setup_default_editor

  menu_define setup_default_agent "Default Agent"
  setup_add_default_item setup_default_agent "${default_agent}" agy "󰫢  Antigravity" setup_default_agent_agy agy
  setup_add_default_item setup_default_agent "${default_agent}" claude "󰛄  Claude" setup_default_agent_claude claude
  setup_add_default_item setup_default_agent "${default_agent}" codex "󱙺  Codex" setup_default_agent_codex codex
  setup_add_default_item setup_default_agent "${default_agent}" copilot "  Copilot" setup_default_agent_copilot copilot
  setup_add_default_item setup_default_agent "${default_agent}" crush "󰋑  Crush" setup_default_agent_crush crush
  setup_add_default_item setup_default_agent "${default_agent}" grok "󰧑  Grok" setup_default_agent_grok grok
  setup_add_default_item setup_default_agent "${default_agent}" omp "󰚩  Oh My Pi" setup_default_agent_omp omp
  setup_add_default_item setup_default_agent "${default_agent}" opencode "󰚩  OpenCode" setup_default_agent_opencode opencode
  setup_add_default_item setup_default_agent "${default_agent}" ori "󰚩  Ori" setup_default_agent_ori ori
  setup_add_default_item setup_default_agent "${default_agent}" pi "󰚩  Pi" setup_default_agent_pi pi

  menu_define setup_default_browser "Default Browser"
  setup_add_default_item setup_default_browser "${default_browser}" chromium "  Chromium" setup_default_browser_chromium chromium
  setup_add_default_item setup_default_browser "${default_browser}" chrome "󰊯  Chrome" setup_default_browser_chrome google-chrome-stable
  setup_add_default_item setup_default_browser "${default_browser}" brave "󰖟  Brave" setup_default_browser_brave brave
  setup_add_default_item setup_default_browser "${default_browser}" brave-origin "󰖟  Brave Origin" setup_default_browser_brave-origin brave-origin
  setup_add_default_item setup_default_browser "${default_browser}" edge "󰇩  Edge" setup_default_browser_edge microsoft-edge-stable
  setup_add_default_item setup_default_browser "${default_browser}" firefox "  Firefox" setup_default_browser_firefox firefox
  setup_add_default_item setup_default_browser "${default_browser}" zen "󰖟  Zen" setup_default_browser_zen zen-browser

  menu_define setup_default_terminal "Default Terminal"
  setup_add_default_item setup_default_terminal "${default_terminal}" alacritty "  Alacritty" setup_default_terminal_alacritty alacritty
  setup_add_default_item setup_default_terminal "${default_terminal}" foot "  Foot" setup_default_terminal_foot foot
  setup_add_default_item setup_default_terminal "${default_terminal}" ghostty "  Ghostty" setup_default_terminal_ghostty ghostty
  setup_add_default_item setup_default_terminal "${default_terminal}" kitty "  Kitty" setup_default_terminal_kitty kitty

  menu_define setup_default_editor "Default Editor"
  setup_add_default_item setup_default_editor "${default_editor}" nvim "  Neovim" setup_default_editor_nvim nvim
  setup_add_default_item setup_default_editor "${default_editor}" code "  VSCode" setup_default_editor_code code
  setup_add_default_item setup_default_editor "${default_editor}" cursor "  Cursor" setup_default_editor_cursor cursor
  setup_add_default_item setup_default_editor "${default_editor}" zeditor "  Zed" setup_default_editor_zeditor zeditor
  setup_add_default_item setup_default_editor "${default_editor}" sublime_text "  Sublime Text" setup_default_editor_sublime_text sublime_text
  setup_add_default_item setup_default_editor "${default_editor}" hx "  Helix" setup_default_editor_hx hx
  setup_add_default_item setup_default_editor "${default_editor}" vim "  Vim" setup_default_editor_vim vim
  setup_add_default_item setup_default_editor "${default_editor}" emacs "  Emacs" setup_default_editor_emacs emacs

  menu_define setup_security "Security"
  menu_add_item setup_security "󰈷  Fingerprint" action setup_security_fingerprint
  menu_add_item setup_security "  Fido2" action setup_security_fido2
  menu_add_item setup_security "󰣀  SSHD" action setup_security_sshd
  menu_add_item setup_security "󰟵  Passwordless Sudo" action setup_security_passwordless_sudo
  menu_add_item setup_security "󰡨  Sudoless Docker" action setup_security_sudoless_docker

  [[ -f ~/.config/hypr/keybindings.lua ]] && menu_add_item setup "  Keybindings" action setup_keybindings
}

menu_run_action_setup() {
  local action_id="$1"

  case "${action_id}" in
    setup_default_agent_*) hyprshell setup/default.sh agent "${action_id#setup_default_agent_}" ;;
    setup_default_browser_*) hyprshell setup/default.sh browser "${action_id#setup_default_browser_}" ;;
    setup_default_terminal_*) hyprshell setup/default.sh terminal "${action_id#setup_default_terminal_}" ;;
    setup_default_editor_*) hyprshell setup/default.sh editor "${action_id#setup_default_editor_}" ;;
    setup_audio) present_terminal --hypr-profile tui --app-id org.tui.Wiremix --title Wiremix -- wiremix ;;
    setup_wifi) rfkill unblock wifi && present_terminal --hypr-profile tui --app-id org.tui.Impala --title Impala -- impala ;;
    setup_bluetooth) rfkill unblock bluetooth && present_terminal --hypr-profile tui --app-id org.tui.Bluetui --title Bluetui -- bluetui ;;
    setup_network) present_terminal --hypr-profile tui --app-id org.tui.Oryx --title Oryx -- sudo oryx ;;
    setup_monitors_config) open_in_editor ~/.config/hypr/monitors.lua ;;
    setup_monitor_scale) hyprshell rofi/run-after-close.sh -- hyprshell system/monitor-scale.sh --select ;;
    setup_monitor_laptop_toggle) hyprshell system/monitor-internal.sh toggle ;;
    setup_monitor_mirror_toggle) hyprshell system/monitor-mirror.sh toggle ;;
    setup_keybindings) open_in_editor ~/.config/hypr/keybindings.lua ;;
    setup_dns) present_terminal hyprshell install/dns.sh ;;
    setup_wifi_qr) present_terminal --app-id org.tui.WifiQr --title "Wi-Fi QR" -- hyprshell util/wifi-pass.sh --qr ;;
    setup_security_fingerprint) present_terminal hyprshell install/fingerprint.sh ;;
    setup_security_fido2) present_terminal hyprshell install/fido2.sh ;;
    setup_security_sshd) present_terminal hyprshell install/sshd.sh ;;
    setup_security_passwordless_sudo) present_terminal hyprshell install/passwordless-sudo.sh ;;
    setup_security_sudoless_docker) present_terminal hyprshell install/sudoless-docker.sh ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_setup
