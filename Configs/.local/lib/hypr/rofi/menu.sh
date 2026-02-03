#!/usr/bin/env bash

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

# Set to true when going directly to a submenu, so we can exit directly
BACK_TO_EXIT=false

back_to() {
  local parent_menu="$1"

  if [[ "$BACK_TO_EXIT" == "true" ]]; then
    exit 0
  elif [[ -n "$parent_menu" ]]; then
    "$parent_menu"
  else
    show_main_menu
  fi
}

menu() {
  local prompt="$1"
  local options="$2"
  local extra="$3"
  local preselect="$4"

  local rofi_args=()

  hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
  hypr_border=${hypr_border:-2}
  elem_border=$((hypr_border / 2))

  font_scale="${ROFI_MENU_SCALE:-$ROFI_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  font_name=${ROFI_MENU_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}

  # Get screen height and calculate max height (80% of screen)
  local screen_height=$(hyprctl -j monitors | jq '.[0].height')
  local max_height=$((screen_height * 90 / 100))

  rofi_args+=("-theme-str" "* {font: \"${font_name} ${font_scale}\";}")
  rofi_args+=("-theme-str" "window {border-radius: ${hypr_border}px; max-height: ${max_height}px;}")
  rofi_args+=("-theme-str" "element {border-radius: ${hypr_border}px;}")
  rofi_args+=("-theme-str" "textbox-prompt-colon {border-radius: ${elem_border}px; str: \"$prompt\";}")
  rofi_args+=("-theme-str" "entry {placeholder: \"Hello ${USER^}!\";}")
  rofi_args+=("-theme-str" "element selected.normal {border-radius: ${elem_border}px;}")

  # Handle preselection
  if [[ -n "$preselect" ]]; then
    local index
    index=$(echo -e "$options" | grep -nxF "$preselect" | cut -d: -f1)
    if [[ -n "$index" ]]; then
      # rofi uses 0-based indexing, grep uses 1-based
      rofi_args+=("-selected-row" "$((index - 1))")
    fi
  fi

  echo -e "$options" | rofi -dmenu -i -no-show-icons -p "$prompt" -theme menutree "${rofi_args[@]}" 2>/dev/null
}

terminal() {
  xdg-terminal-exec --app-id=org.tui.Omarchy "$@"
}

present_terminal() {
  local app_id=""
  local title=""
  local cmd=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --app-id)
        app_id="$2"
        shift 2
        ;;
      --title)
        title="$2"
        shift 2
        ;;
      --)
        shift
        cmd+=("$@")
        break
        ;;
      *)
        cmd+=("$1")
        shift
        ;;
    esac
  done

  if [[ "${#cmd[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ -n "$app_id" || -n "$title" ]]; then
    hyprshell launch/terminal-present.sh --app-id "${app_id:-org.tui.Terminal}" --title "${title:-Terminal}" -- "${cmd[@]}"
  else
    hyprshell launch/terminal-present.sh -- "${cmd[@]}"
  fi
}

open_in_editor() {
  notify-send "Editing config file" "$1"
  hyprshell launch/editor.sh "$1"
}

install() {
  present_terminal "echo 'Installing $1...'; sudo pacman -S --noconfirm $2"
}

install_and_launch() {
  present_terminal "echo 'Installing $1...'; sudo pacman -S --noconfirm $2 && setsid gtk-launch $3"
}

install_font() {
  present_terminal "echo 'Installing $1...'; sudo pacman -S --noconfirm --needed $2 && sleep 2 && hyprshell fonts/font-set.sh '$3'"
}

get_aur_helper() {
  if command -v yay &>/dev/null; then
    echo "yay"
  elif command -v paru &>/dev/null; then
    echo "paru"
  else
    echo "yay" # Default, will fail with helpful message
  fi
}

aur_install() {
  local aur_helper
  aur_helper=$(get_aur_helper)
  present_terminal "echo 'Installing $1 from AUR...'; $aur_helper -S --noconfirm $2"
}

aur_install_and_launch() {
  local aur_helper
  aur_helper=$(get_aur_helper)
  present_terminal "echo 'Installing $1 from AUR...'; $aur_helper -S --noconfirm $2 && setsid gtk-launch $3"
}

show_learn_menu() {
  case $(menu "Learn" "  Keybindings\n  Neovim\n󱆃  Scripting") in
    *Keybindings*) hyprshell keybinds_hint.sh c ;;
    *Neovim*) show_neovim_menu ;;
    *Scripting*) show_scripting_menu ;;
    *) show_main_menu ;;
  esac
}

show_neovim_menu() {
  case $(menu "Neovim" "󰈙  Neovim Docs\n󰞋  Built-in Help\n  Lua Guide\n󰑓  Kickstart.nvim\n󰏗  Plugin Development\n  Keymaps Cheatsheet") in
    *"Neovim Docs"*) hyprshell launch/webapp.sh "https://neovim.io/doc/" ;;
    *"Built-in Help"*) present_terminal "nvim +':help' +only" ;;
    *"Lua Guide"*) hyprshell launch/webapp.sh "https://neovim.io/doc/user/lua-guide.html" ;;
    *"Kickstart.nvim"*) hyprshell launch/webapp.sh "https://github.com/nvim-lua/kickstart.nvim" ;;
    *"Plugin Development"*) hyprshell launch/webapp.sh "https://github.com/nanotee/nvim-lua-guide" ;;
    *"Keymaps Cheatsheet"*) hyprshell launch/webapp.sh "https://vim.rtorr.com/" ;;
    *) show_learn_menu ;;
  esac
}

show_scripting_menu() {
  case $(menu "Scripting" "󱆃  Bash\n  Python\n  hyprctl\n󰘦  jq\n󰒋  systemd\n󰙲  D-Bus\n󰉵  udev") in
    *Bash*) show_bash_scripting_menu ;;
    *Python*) show_python_scripting_menu ;;
    *hyprctl*) hyprshell launch/webapp.sh "https://wiki.hyprland.org/Configuring/Using-hyprctl/" ;;
    *jq*) hyprshell launch/webapp.sh "https://jqlang.github.io/jq/manual/" ;;
    *systemd*) hyprshell launch/webapp.sh "https://www.freedesktop.org/software/systemd/man/latest/" ;;
    *D-Bus*) hyprshell launch/webapp.sh "https://dbus.freedesktop.org/doc/dbus-tutorial.html" ;;
    *udev*) hyprshell launch/webapp.sh "https://wiki.archlinux.org/title/Udev" ;;
    *) show_learn_menu ;;
  esac
}

show_bash_scripting_menu() {
  case $(menu "Bash Scripting" "󱆃  Bash Cheatsheet\n󰄬  ShellCheck\n  POSIX Shell\n󰅍  wl-clipboard\n  grim/slurp\n  wf-recorder\n󰂚  notify-send") in
    *"Bash Cheatsheet"*) hyprshell launch/webapp.sh "https://devhints.io/bash" ;;
    *ShellCheck*) hyprshell launch/webapp.sh "https://www.shellcheck.net/wiki/" ;;
    *"POSIX Shell"*) hyprshell launch/webapp.sh "https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html" ;;
    *wl-clipboard*) hyprshell launch/webapp.sh "https://github.com/bugaevc/wl-clipboard" ;;
    *"grim/slurp"*) hyprshell launch/webapp.sh "https://sr.ht/~emersion/grim/" ;;
    *wf-recorder*) hyprshell launch/webapp.sh "https://github.com/ammen99/wf-recorder" ;;
    *notify-send*) hyprshell launch/webapp.sh "https://wiki.archlinux.org/title/Desktop_notifications" ;;
    *) show_scripting_menu ;;
  esac
}

show_python_scripting_menu() {
  case $(menu "Python Scripting" "  Python Docs\n󰏓  pip/pipx\n󰮲  PyGObject\n󱃾  subprocess\n  pywal\n󰙲  pydbus\n󰉋  pathlib\n󰘦  argparse\n󰖟  requests\n󰍛  psutil") in
    *"Python Docs"*) hyprshell launch/webapp.sh "https://docs.python.org/3/" ;;
    *pip/pipx*) hyprshell launch/webapp.sh "https://packaging.python.org/en/latest/guides/tool-recommendations/" ;;
    *PyGObject*) hyprshell launch/webapp.sh "https://pygobject.readthedocs.io/" ;;
    *subprocess*) hyprshell launch/webapp.sh "https://docs.python.org/3/library/subprocess.html" ;;
    *pywal*) hyprshell launch/webapp.sh "https://github.com/dylanaraps/pywal/wiki" ;;
    *pydbus*) hyprshell launch/webapp.sh "https://github.com/LEW21/pydbus" ;;
    *pathlib*) hyprshell launch/webapp.sh "https://docs.python.org/3/library/pathlib.html" ;;
    *argparse*) hyprshell launch/webapp.sh "https://docs.python.org/3/library/argparse.html" ;;
    *requests*) hyprshell launch/webapp.sh "https://requests.readthedocs.io/" ;;
    *psutil*) hyprshell launch/webapp.sh "https://psutil.readthedocs.io/" ;;
    *) show_scripting_menu ;;
  esac
}

show_trigger_menu() {
  case $(menu "Trigger" "  Capture\n  Share\n󰔎  Toggle") in
    *Capture*) show_capture_menu ;;
    *Share*) show_share_menu ;;
    *Toggle*) show_toggle_menu ;;
    *) show_main_menu ;;
  esac
}

show_capture_menu() {
  case $(menu "Capture" "  Screenshot\n  Screenrecord\n󰃉  Color") in
    *Screenshot*) show_screenshot_menu ;;
    *Screenrecord*) show_screenrecord_menu ;;
    *Color*) hyprshell colorpicker.sh ;;
    *) show_trigger_menu ;;
  esac
}

show_screenshot_menu() {
  case $(menu "Screenshot" "  Snap with Editing\n  Straight to Clipboard") in
    *Editing*) hyprshell screenshot.sh smart ;;
    *Clipboard*) hyprshell screenshot.sh smart clipboard ;;
    *) show_capture_menu ;;
  esac
}

show_screenrecord_menu() {
  case $(menu "Screenrecord" "  Region\n  Region + Audio\n  Display\n  Display + Audio\n") in
    *"Region + Audio"*) hyprshell screenrecord.sh --start --audio ;;
    *"Region"*) hyprshell screenrecord.sh --start ;;
    *"Display + Audio"*) hyprshell screenrecord.sh --start --output --audio ;;
    *"Display"*) hyprshell screenrecord.sh --start --output ;;
    *) back_to show_capture_menu ;;
  esac
}

show_share_menu() {
  case $(menu "Share" "  Clipboard\n  File \n  Folder") in
    *Clipboard*) terminal bash -c "hyprshell cmd/share.sh clipboard" ;;
    *File*) terminal bash -c "hyprshell cmd/share.sh file" ;;
    *Folder*) terminal bash -c "hyprshell cmd/share.sh folder" ;;
    *) back_to show_trigger_menu ;;
  esac
}

show_toggle_menu() {
  case $(menu "Toggle" "󰔎  Nightlight\n󱫖  Keep Awake\n󰍜  Waybar") in
    *Nightlight*) hyprshell hyprsunset --toggle && pkill waybar ;;
    *Keep*) hyprshell session/toggle-keep-awake.sh ;;
    *Waybar*) hyprshell waybar.py --hide ;;
    *) show_trigger_menu ;;
  esac
}

show_style_menu() {
  case $(menu "Style" "󰸌  Theme\n  Wallpaper\n  Font") in
    *Theme*) hyprshell theme.select.sh ;;
    *Wallpaper*) hyprshell wallpaper.sh -SG ;;
    *Font*) show_font_menu ;;
    *) show_main_menu ;;
  esac
}

show_font_menu() {
  local font_list
  font_list="$(hyprshell fonts/font-list.sh)"

  local font
  font="$(menu "Select Font" "${font_list}")"
  if [[ -z "$font" || "$font" == "CNCLD" ]]; then
    back_to show_style_menu
  fi

  hyprshell fonts/font-set.sh "$font" >/dev/null 2>&1 &
  exit 0
}

show_setup_menu() {
  local options="󰜟  Audio\n  Wifi\n  Bluetooth\n󱫋  Network\n  Power Profile\n󰍹  Monitors"
  [ -f ~/.config/hypr/bindings.conf ] && options="$options\n  Keybindings"
  [ -f ~/.config/hypr/input.conf ] && options="$options\n  Input"
  options="$options\n DNS\n  Security"

  case $(menu "Setup" "$options") in
    *Audio*) present_terminal --app-id org.tui.Wiremix --title Wiremix wiremix ;;
    *Wifi*)
      rfkill unblock wifi
      hyprshell launch/wifi.sh
      ;;
    *Bluetooth*)
      rfkill unblock bluetooth
      present_terminal --app-id org.tui.Bluetui --title Bluetui bluetui
      ;;
    *Network*) present_terminal --app-id org.tui.Oryx --title Oryx sudo oryx ;;
    *Power*) show_setup_power_menu ;;
    *Monitors*) open_in_editor ~/.config/hypr/monitors.conf ;;
    *Keybindings*) open_in_editor ~/.config/hypr/bindings.conf ;;
    *Input*) open_in_editor ~/.config/hypr/input.conf ;;
    *DNS*) present_terminal hyprshell setup/dns.sh ;;
    *Security*) show_setup_security_menu ;;
    *) show_main_menu ;;
  esac
}

show_dev_tools_menu() {
  case $(menu "Dev Tools" "󰊢  Git (LazyGit)\n  Docker (LazyDocker)\n  File Manager (Ranger)\n󰻠  CPU Monitor (Htop)\n  GPU Monitor (Nvtop)\n  Disk Usage (Dua)\n  Music Player (Rmpc)") in
    *Git*) hyprshell launch/lazygit.sh ;;
    *Docker*) hyprshell launch/lazydocker.sh ;;
    *File*) present_terminal --app-id org.tui.Ranger --title Ranger ranger ;;
    *CPU*) present_terminal --app-id org.tui.Htop --title Htop htop ;;
    *GPU*) present_terminal --app-id org.tui.Nvtop --title Nvtop nvtop ;;
    *Disk*) present_terminal --app-id org.tui.Dua --title Dua dua i ;;
    *Music*) present_terminal --app-id org.tui.Rmpc --title Rmpc rmpc ;;
    *) show_main_menu ;;
  esac
}

show_setup_power_menu() {
  profile=$(menu "Power Profile" "$(hyprshell system/powerprofiles.sh)" "" "$(powerprofilesctl get)")

  if [[ "$profile" == "CNCLD" || -z "$profile" ]]; then
    back_to show_setup_menu
  else
    powerprofilesctl set "$profile"
  fi
}

show_setup_security_menu() {
  case $(menu "Setup" "󰈷  Fingerprint\n  Fido2") in
    *Fingerprint*) present_terminal hyprshell setup/fingerprint.sh ;;
    *Fido2*) present_terminal hyprshell setup/fido2.sh ;;
    *) show_setup_menu ;;
  esac
}

show_install_menu() {
  case $(menu "Install" "󰣇  Package\n󰣇  AUR\n  Web App\n  TUI\n  Font\n󰵮  Development\n󰍲  Windows\n  Gaming") in
    *Package*) terminal hyprshell pkg/install.sh ;;
    *AUR*) terminal hyprshell pkg/aur-install.sh ;;
    *Web*) present_terminal hyprshell install/webapp.sh ;;
    *TUI*) present_terminal hyprshell install/tui.sh ;;
    *Font*) show_install_font_menu ;;
    *Development*) show_install_development_menu ;;
    *AI*) show_install_ai_menu ;;
    *Windows*) present_terminal "hyprshell vm/windows.sh install" ;;
    *Gaming*) show_install_gaming_menu ;;
    *) show_main_menu ;;
  esac
}

show_install_ai_menu() {
  ollama_pkg=$(
    (command -v nvidia-smi &>/dev/null && echo ollama-cuda) \
      || (command -v rocminfo &>/dev/null && echo ollama-rocm) \
      || echo ollama
  )

  case $(menu "Install" "󱚤  Claude Code\n󱚤  Cursor CLI\n󱚤  Gemini\n󱚤  OpenAI Codex\n󱚤  LM Studio\n󱚤  Ollama\n󱚤  Crush\n󱚤  opencode") in
    *Claude*) install "Claude Code" "claude-code" ;;
    *Cursor*) install "Cursor CLI" "cursor-cli" ;;
    *OpenAI*) install "OpenAI Codex" "openai-codex-bin" ;;
    *Gemini*) install "Gemini" "gemini-cli" ;;
    *Studio*) install "LM Studio" "lmstudio" ;;
    *Ollama*) install "Ollama" $ollama_pkg ;;
    *Crush*) install "Crush" "crush-bin" ;;
    *opencode*) install "opencode" "opencode" ;;
    *) show_install_menu ;;
  esac
}

show_install_gaming_menu() {
  case $(menu "Install" "  Steam\n  RetroArch [AUR]\n󰍳  Minecraft") in
    *Steam*) present_terminal hyprshell gaming/install-steam.sh ;;
    *RetroArch*) aur_install_and_launch "RetroArch" "retroarch retroarch-assets libretro libretro-fbneo" "com.libretro.RetroArch.desktop" ;;
    *Minecraft*) install_and_launch "Minecraft" "minecraft-launcher" "minecraft-launcher" ;;
    *) show_install_menu ;;
  esac
}

show_install_development_menu() {
  case $(menu "Install" "󰫏  Ruby on Rails\n  Docker DB\n  JavaScript\n  Go\n  PHP\n  Python\n  Elixir\n  Zig\n  Rust\n  Java\n  .NET\n  OCaml\n  Clojure") in
    *Rails*) present_terminal "hyprshell install/dev-env.sh ruby" ;;
    *Docker*) present_terminal hyprshell install/docker-dbs.sh ;;
    *JavaScript*) show_install_javascript_menu ;;
    *Go*) present_terminal "hyprshell install/dev-env.sh go" ;;
    *PHP*) show_install_php_menu ;;
    *Python*) present_terminal "hyprshell install/dev-env.sh python" ;;
    *Elixir*) show_install_elixir_menu ;;
    *Zig*) present_terminal "hyprshell install/dev-env.sh zig" ;;
    *Rust*) present_terminal "hyprshell install/dev-env.sh rust" ;;
    *Java*) present_terminal "hyprshell install/dev-env.sh java" ;;
    *NET*) present_terminal "hyprshell install/dev-env.sh dotnet" ;;
    *OCaml*) present_terminal "hyprshell install/dev-env.sh ocaml" ;;
    *Clojure*) present_terminal "hyprshell install/dev-env.sh clojure" ;;
    *) show_install_menu ;;
  esac
}

show_install_javascript_menu() {
  case $(menu "Install" "  Node.js\n  Bun\n  Deno") in
    *Node*) present_terminal "hyprshell install/dev-env.sh node" ;;
    *Bun*) present_terminal "hyprshell install/dev-env.sh bun" ;;
    *Deno*) present_terminal "hyprshell install/dev-env.sh deno" ;;
    *) show_install_development_menu ;;
  esac
}

show_install_php_menu() {
  case $(menu "Install" "  PHP\n  Laravel\n  Symfony") in
    *PHP*) present_terminal "hyprshell install/dev-env.sh php" ;;
    *Laravel*) present_terminal "hyprshell install/dev-env.sh laravel" ;;
    *Symfony*) present_terminal "hyprshell install/dev-env.sh symfony" ;;
    *) show_install_development_menu ;;
  esac
}

show_install_elixir_menu() {
  case $(menu "Install" "  Elixir\n  Phoenix") in
    *Elixir*) present_terminal "hyprshell install/dev-env.sh elixir" ;;
    *Phoenix*) present_terminal "hyprshell install/dev-env.sh phoenix" ;;
    *) show_install_development_menu ;;
  esac
}

show_install_font_menu() {
  case $(menu "Install" "  Meslo LG Mono\n  Fira Code\n  Victor Code\n  Bistream Vera Mono" "--width 350") in
    *Meslo*) install_font "Meslo LG Mono" "ttf-meslo-nerd" "MesloLGL Nerd Font" ;;
    *Fira*) install_font "Fira Code" "ttf-firacode-nerd" "FiraCode Nerd Font" ;;
    *Victor*) install_font "Victor Code" "ttf-victor-mono-nerd" "VictorMono Nerd Font" ;;
    *Bistream*) install_font "Bistream Vera Code" "ttf-bitstream-vera-mono-nerd" "BitstromWera Nerd Font" ;;
    *) show_install_menu ;;
  esac
}

show_remove_menu() {
  case $(menu "Remove" "󰣇  Package\n  Web App\n  TUI\n󰍲  Windows\n󰈷  Fingerprint\n  Fido2") in
    *Package*) terminal hyprshell pkg/remove.sh ;;
    *Web*) present_terminal hyprshell install/webapp-remove.sh ;;
    *TUI*) present_terminal hyprshell install/tui-remove.sh ;;
    *Windows*) present_terminal "hyprshell vm/windows.sh remove" ;;
    *Fingerprint*) present_terminal "hyprshell setup/fingerprint.sh --remove" ;;
    *Fido2*) present_terminal "hyprshell setup/fido2.sh --remove" ;;
    *) show_main_menu ;;
  esac
}

show_update_menu() {
  case $(menu "Update" "  Config\n  Process\n󰇅  Hardware\n  Firmware\n  Password\n  Timezone\n  Time") in
    *Config*) show_update_config_menu ;;
    *Process*) show_update_process_menu ;;
    *Hardware*) show_update_hardware_menu ;;
    *Firmware*) present_terminal hyprshell system/firmware.sh ;;
    *Timezone*) present_terminal hyprshell system/timezone.sh ;;
    *Time*) present_terminal hyprshell system/time.sh ;;
    *Password*) show_update_password_menu ;;
    *) show_main_menu ;;
  esac
}

show_update_process_menu() {
  case $(menu "Restart" "  Hypridle\n  Hyprsunset\n  Swayosd\n󰌧  Walker\n󰍜  Waybar") in
    *Hypridle*) hyprshell service/restart-hypridle.sh ;;
    *Hyprsunset*) hyprshell service/restart-hyprsunset.sh ;;
    *Swayosd*) hyprshell service/restart-swayosd.sh ;;
    *Walker*) hyprshell service/restart-walker.sh ;;
    *Waybar*) hyprshell service/restart-waybar.sh ;;
    *) show_update_menu ;;
  esac
}

show_update_config_menu() {
  case $(menu "Use default config" "  Hyprland\n  Hypridle\n  Hyprlock\n  Hyprsunset\n󱣴  Plymouth\n  Swayosd\n󰌧  Walker\n󰍜  Waybar") in
    *Hyprland*) present_terminal hyprshell service/refresh-hyprland.sh ;;
    *Hypridle*) present_terminal hyprshell service/refresh-hypridle.sh ;;
    *Hyprlock*) present_terminal hyprshell service/refresh-hyprlock.sh ;;
    *Hyprsunset*) present_terminal hyprshell service/refresh-hyprsunset.sh ;;
    *Plymouth*) present_terminal hyprshell service/refresh-plymouth.sh ;;
    *Swayosd*) present_terminal hyprshell service/refresh-swayosd.sh ;;
    *Walker*) present_terminal hyprshell service/refresh-walker.sh ;;
    *Waybar*) present_terminal hyprshell service/refresh-waybar.sh ;;
    *) show_update_menu ;;
  esac
}

show_update_hardware_menu() {
  case $(menu "Restart" "  Audio\n󱚾  Wi-Fi\n󰂯  Bluetooth") in
    *Audio*) present_terminal hyprshell service/restart-pipewire.sh ;;
    *Wi-Fi*) present_terminal hyprshell service/restart-wifi.sh ;;
    *Bluetooth*) present_terminal hyprshell service/restart-bluetooth.sh ;;
    *) show_update_menu ;;
  esac
}

show_update_password_menu() {
  case $(menu "Update Password" "  Drive Encryption\n  User") in
    *Drive*) present_terminal hyprshell drive-set-password.sh ;;
    *User*) present_terminal passwd ;;
    *) show_update_menu ;;
  esac
}

show_system_menu() {
  case $(menu "System" "  Lock\n󰤄  Suspend\n󰜉  Restart\n󰐥  Shutdown") in
    *Lock*) hyprshell session/lock.sh ;;
    *Suspend*) systemctl suspend ;;
    *Restart*) hyprshell cmd-restart ;;
    *Shutdown*) hyprshell util/state.sh clear re*-required && systemctl poweroff --no-wall ;;
    *) back_to show_main_menu ;;
  esac
}

show_search_all_menu() {
  local flat_list=""

  # Helper function to add items (reduces duplication)
  add() {
    local path="$1"
    local command="$2"
    flat_list+="${path}|${command}\n"
  }

  # The only maintenance needed: when you add a menu item to any show_*_menu function,
  # add the same item here. The path and command are taken directly from the menu.

  # Dev Tools (from show_dev_tools_menu)
  add "Dev › Git (LazyGit)" "hyprshell launch/lazygit.sh"
  add "Dev › Docker (LazyDocker)" "hyprshell launch/lazydocker.sh"
  add "Dev › File Manager (Ranger)" "present_terminal --app-id org.tui.Ranger --title Ranger ranger"
  add "Dev › CPU Monitor (Htop)" "present_terminal --app-id org.tui.Htop --title Htop htop"
  add "Dev › GPU Monitor (Nvtop)" "present_terminal --app-id org.tui.Nvtop --title Nvtop nvtop"
  add "Dev › Disk Usage (Dua)" "present_terminal --app-id org.tui.Dua --title Dua dua i"
  add "Dev › Music Player (Rmpc)" "present_terminal --app-id org.tui.Rmpc --title Rmpc rmpc"

  # Learn (from show_learn_menu)
  add "Learn › Keybindings" "hyprshell keybinds_hint.sh c"

  # Learn › Neovim (from show_neovim_menu)
  add "Learn › Neovim › Docs" "hyprshell launch/webapp.sh https://neovim.io/doc/"
  add "Learn › Neovim › Built-in Help" "present_terminal 'nvim +\":help\" +only'"
  add "Learn › Neovim › Lua Guide" "hyprshell launch/webapp.sh https://neovim.io/doc/user/lua-guide.html"
  add "Learn › Neovim › Kickstart.nvim" "hyprshell launch/webapp.sh https://github.com/nvim-lua/kickstart.nvim"
  add "Learn › Neovim › Plugin Development" "hyprshell launch/webapp.sh https://github.com/nanotee/nvim-lua-guide"
  add "Learn › Neovim › Keymaps Cheatsheet" "hyprshell launch/webapp.sh https://vim.rtorr.com/"

  # Learn › Scripting (from show_scripting_menu)
  add "Learn › Scripting › hyprctl" "hyprshell launch/webapp.sh https://wiki.hyprland.org/Configuring/Using-hyprctl/"
  add "Learn › Scripting › jq" "hyprshell launch/webapp.sh https://jqlang.github.io/jq/manual/"
  add "Learn › Scripting › systemd" "hyprshell launch/webapp.sh https://www.freedesktop.org/software/systemd/man/latest/"
  add "Learn › Scripting › D-Bus" "hyprshell launch/webapp.sh https://dbus.freedesktop.org/doc/dbus-tutorial.html"
  add "Learn › Scripting › udev" "hyprshell launch/webapp.sh https://wiki.archlinux.org/title/Udev"

  # Learn › Scripting › Bash (from show_bash_scripting_menu)
  add "Learn › Scripting › Bash › Cheatsheet" "hyprshell launch/webapp.sh https://devhints.io/bash"
  add "Learn › Scripting › Bash › ShellCheck" "hyprshell launch/webapp.sh https://www.shellcheck.net/wiki/"
  add "Learn › Scripting › Bash › POSIX Shell" "hyprshell launch/webapp.sh https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html"
  add "Learn › Scripting › Bash › wl-clipboard" "hyprshell launch/webapp.sh https://github.com/bugaevc/wl-clipboard"
  add "Learn › Scripting › Bash › grim/slurp" "hyprshell launch/webapp.sh https://sr.ht/~emersion/grim/"
  add "Learn › Scripting › Bash › wf-recorder" "hyprshell launch/webapp.sh https://github.com/ammen99/wf-recorder"
  add "Learn › Scripting › Bash › notify-send" "hyprshell launch/webapp.sh https://wiki.archlinux.org/title/Desktop_notifications"

  # Learn › Scripting › Python (from show_python_scripting_menu)
  add "Learn › Scripting › Python › Docs" "hyprshell launch/webapp.sh https://docs.python.org/3/"
  add "Learn › Scripting › Python › pip/pipx" "hyprshell launch/webapp.sh https://packaging.python.org/en/latest/guides/tool-recommendations/"
  add "Learn › Scripting › Python › PyGObject" "hyprshell launch/webapp.sh https://pygobject.readthedocs.io/"
  add "Learn › Scripting › Python › subprocess" "hyprshell launch/webapp.sh https://docs.python.org/3/library/subprocess.html"
  add "Learn › Scripting › Python › pywal" "hyprshell launch/webapp.sh https://github.com/dylanaraps/pywal/wiki"
  add "Learn › Scripting › Python › pydbus" "hyprshell launch/webapp.sh https://github.com/LEW21/pydbus"
  add "Learn › Scripting › Python › pathlib" "hyprshell launch/webapp.sh https://docs.python.org/3/library/pathlib.html"
  add "Learn › Scripting › Python › argparse" "hyprshell launch/webapp.sh https://docs.python.org/3/library/argparse.html"
  add "Learn › Scripting › Python › requests" "hyprshell launch/webapp.sh https://requests.readthedocs.io/"
  add "Learn › Scripting › Python › psutil" "hyprshell launch/webapp.sh https://psutil.readthedocs.io/"

  # Trigger › Screenshot (from show_screenshot_menu)
  add "Trigger › Screenshot › Snap with Editing" "hyprshell screenshot.sh smart"
  add "Trigger › Screenshot › Straight to Clipboard" "hyprshell screenshot.sh smart clipboard"

  # Trigger › Screenrecord (from show_screenrecord_menu)
  add "Trigger › Screenrecord › Region" "hyprshell screenrecord.sh --start"
  add "Trigger › Screenrecord › Region + Audio" "hyprshell screenrecord.sh --start --audio"
  add "Trigger › Screenrecord › Display" "hyprshell screenrecord.sh --start --output"
  add "Trigger › Screenrecord › Display + Audio" "hyprshell screenrecord.sh --start --output --audio"

  # Trigger › Capture › Color (from show_capture_menu)
  add "Trigger › Capture › Color Picker" "hyprshell colorpicker.sh"

  # Trigger › Share (from show_share_menu)
  add "Trigger › Share › Clipboard" "terminal bash -c 'hyprshell cmd/share.sh clipboard'"
  add "Trigger › Share › File" "terminal bash -c 'hyprshell cmd/share.sh file'"
  add "Trigger › Share › Folder" "terminal bash -c 'hyprshell cmd/share.sh folder'"

  # Trigger › Toggle (from show_toggle_menu)
  add "Trigger › Toggle › Nightlight" "hyprshell toggle/nightlight.sh"
  add "Trigger › Toggle › Keep Awake" "hyprshell session/toggle-keep-awake.sh"
  add "Trigger › Toggle › Waybar" "hyprshell waybar.py --hide"

  # Style (from show_style_menu)
  add "Style › Theme" "hyprshell theme.select.sh"
  add "Style › Wallpaper" "hyprshell wallpaper.sh -SG"
  add "Style › Font" "show_font_menu"

  # Setup (from show_setup_menu)
  add "Setup › Audio" "present_terminal --app-id org.tui.Wiremix --title Wiremix wiremix"
  add "Setup › Wifi" "rfkill unblock wifi && hyprshell launch/wifi.sh"
  add "Setup › Bluetooth" "rfkill unblock bluetooth && present_terminal --app-id org.tui.Bluetui --title Bluetui bluetui"
  add "Setup › Network" "present_terminal --app-id org.tui.Oryx --title Oryx sudo oryx"
  add "Setup › Monitors" "open_in_editor ~/.config/hypr/monitors.conf"
  add "Setup › Keybindings" "open_in_editor ~/.config/hypr/bindings.conf"
  add "Setup › Input" "open_in_editor ~/.config/hypr/input.conf"
  add "Setup › DNS" "present_terminal hyprshell setup/dns.sh"

  # Setup › Security (from show_setup_security_menu)
  add "Setup › Security › Fingerprint" "present_terminal hyprshell setup/fingerprint.sh"
  add "Setup › Security › Fido2" "present_terminal hyprshell setup/fido2.sh"

  # System (from show_system_menu)
  add "System › Shutdown" "hyprshell util/state.sh clear re*-required && systemctl poweroff --no-wall"
  add "System › Reboot" "hyprshell util/state.sh clear re*-required && systemctl reboot --no-wall"
  add "System › Lock" "hyprshell session/lock.sh"
  add "System › Logout" "hyprshell util/confirm.sh --logout"
  add "System › Sleep" "hyprshell util/confirm.sh --suspend"

  # Show menu and execute
  local selection
  selection=$(echo -e "$flat_list" | cut -d'|' -f1 | menu "Search All" "$(cat)")

  if [[ -n "$selection" ]]; then
    local command=$(echo -e "$flat_list" | grep -F "${selection}|" | head -1 | cut -d'|' -f2-)
    if [[ -n "$command" ]]; then
      eval "$command"
    fi
  else
    show_main_menu
  fi
}
show_main_menu() {
  go_to_menu "$(
    menu "Main" "󱡴  Search All\n  Tools\n󰀻  Apps\n  Learn\n󱊨  Trigger\n󰢵  Style\n  Setup\n󰉉  Install\n󰭌  Remove\n  Update\n  System"
  )"
}

go_to_menu() {
  case "${1,,}" in
    *search*) show_search_all_menu ;;
    *tools*) show_dev_tools_menu ;;
    *apps*) hyprshell rofilaunch.sh ;;
    *learn*) show_learn_menu ;;
    *trigger*) show_trigger_menu ;;
    *style*) show_style_menu ;;
    *theme*) hyprshell theme.select.sh ;;
    *wallpaper*) hyprshell wallpaper.sh ;;
    *setup*) show_setup_menu ;;
    *power*) show_setup_power_menu ;;
    *install*) show_install_menu ;;
    *remove*) show_remove_menu ;;
    *update*) show_update_menu ;;
    *system*) show_system_menu ;;
  esac
}

if [[ -n "$1" ]]; then
  BACK_TO_EXIT=true
  go_to_menu "$1"
else
  show_main_menu
fi
