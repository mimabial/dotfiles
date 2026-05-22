#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

install() {
  local name="$1"
  local package_list="$2"
  local -a packages=()
  read -r -a packages <<<"${package_list}"
  present_terminal -- bash -lc '
    name="$1"
    shift
    printf "Installing %s...\n" "$name"
    exec hyprshell pm add "$@"
  ' _ "${name}" "${packages[@]}"
}

aur_install() {
  if ! get_aur_helper >/dev/null; then
    dunstify -i "dialog-error" "AUR Helper Missing" "Install yay or paru to use AUR installs from the menu" -u critical
    return 1
  fi
  local name="$1"
  local package_list="$2"
  local -a packages=()
  read -r -a packages <<<"${package_list}"
  present_terminal -- bash -lc '
    name="$1"
    shift
    printf "Installing %s from AUR...\n" "$name"
    exec hyprshell pm aur-add "$@"
  ' _ "${name}" "${packages[@]}"
}

aur_install_and_launch() {
  if ! get_aur_helper >/dev/null; then
    dunstify -i "dialog-error" "AUR Helper Missing" "Install yay or paru to use AUR installs from the menu" -u critical
    return 1
  fi
  local name="$1"
  local package_list="$2"
  local desktop_id="$3"
  local -a packages=()
  read -r -a packages <<<"${package_list}"
  present_terminal -- bash -lc '
    name="$1"
    desktop_id="$2"
    shift 2
    printf "Installing %s from AUR...\n" "$name"
    if hyprshell pm aur-add "$@"; then
      setsid gtk-launch "$desktop_id"
    fi
  ' _ "${name}" "${desktop_id}" "${packages[@]}"
}

run_dev_env_install() {
  present_terminal -- hyprshell install/dev-env.sh "$1"
}

menu_register_domain_install() {
  menu_define install "Install"
  menu_add_item install "󰣇  Package" action install_package
  menu_add_item install "󰣇  AUR" action install_aur
  menu_add_item install "  Font" action install_font
  menu_add_item install "󰵮  Development" submenu install_development
  menu_add_item install "󱚤  AI" submenu install_ai
  menu_add_item install "  Gaming" submenu install_gaming

  menu_define install_ai "Install"
  menu_add_item install_ai "󱚤  Claude Code" action install_ai_claude
  menu_add_item install_ai "󱚤  Cursor CLI" action install_ai_cursor
  menu_add_item install_ai "󱚤  Gemini" action install_ai_gemini
  menu_add_item install_ai "󱚤  OpenAI Codex" action install_ai_openai
  menu_add_item install_ai "󱚤  LM Studio" action install_ai_lmstudio
  menu_add_item install_ai "󱚤  Ollama" action install_ai_ollama
  menu_add_item install_ai "󱚤  Crush" action install_ai_crush
  menu_add_item install_ai "󱚤  opencode" action install_ai_opencode

  menu_define install_gaming "Install"
  menu_add_item install_gaming "  Steam" action install_gaming_steam
  menu_add_item install_gaming "  RetroArch [AUR]" action install_gaming_retroarch

  menu_define install_development "Install"
  menu_add_item install_development "󰫏  Ruby on Rails" action install_dev_ruby
  menu_add_item install_development "  Docker DB" action install_dev_docker_dbs
  menu_add_item install_development "  JavaScript" submenu install_javascript
  menu_add_item install_development "  Go" action install_dev_go
  menu_add_item install_development "  PHP" submenu install_php
  menu_add_item install_development "  Python" action install_dev_python
  menu_add_item install_development "  Elixir" submenu install_elixir
  menu_add_item install_development "  Zig" action install_dev_zig
  menu_add_item install_development "  Rust" action install_dev_rust
  menu_add_item install_development "  Java" action install_dev_java
  menu_add_item install_development "  .NET" action install_dev_dotnet
  menu_add_item install_development "  OCaml" action install_dev_ocaml
  menu_add_item install_development "  Clojure" action install_dev_clojure
  menu_add_item install_development "Scala" action install_dev_scala

  menu_define install_javascript "Install"
  menu_add_item install_javascript "  Node.js" action install_dev_node
  menu_add_item install_javascript "  Bun" action install_dev_bun
  menu_add_item install_javascript "  Deno" action install_dev_deno

  menu_define install_php "Install"
  menu_add_item install_php "  PHP" action install_dev_php
  menu_add_item install_php "  Laravel" action install_dev_laravel
  menu_add_item install_php "  Symfony" action install_dev_symfony

  menu_define install_elixir "Install"
  menu_add_item install_elixir "  Elixir" action install_dev_elixir
  menu_add_item install_elixir "  Phoenix" action install_dev_phoenix
}

menu_run_action_install() {
  local action_id="$1"
  local ollama_pkg=""

  case "${action_id}" in
    install_package) terminal hyprshell pm install-repo ;;
    install_aur) terminal hyprshell pm install-aur ;;
    install_ai_claude) install "Claude Code" "claude-code" ;;
    install_ai_cursor) install "Cursor CLI" "cursor-cli" ;;
    install_ai_gemini) install "Gemini" "gemini-cli" ;;
    install_ai_openai) install "OpenAI Codex" "openai-codex-bin" ;;
    install_ai_lmstudio) install "LM Studio" "lmstudio" ;;
    install_ai_ollama)
      ollama_pkg=$(
        (command -v nvidia-smi &>/dev/null && echo ollama-cuda) \
          || (command -v rocminfo &>/dev/null && echo ollama-rocm) \
          || echo ollama
      )
      install "Ollama" "${ollama_pkg}"
      ;;
    install_ai_crush) install "Crush" "crush-bin" ;;
    install_ai_opencode) install "opencode" "opencode" ;;
    install_gaming_steam) present_terminal hyprshell gaming/install-steam.sh ;;
    install_gaming_retroarch) aur_install_and_launch "RetroArch" "retroarch retroarch-assets libretro libretro-fbneo" "com.libretro.RetroArch.desktop" ;;
    install_dev_ruby) run_dev_env_install ruby ;;
    install_dev_docker_dbs) present_terminal hyprshell install/docker-dbs.sh ;;
    install_dev_go) run_dev_env_install go ;;
    install_dev_python) run_dev_env_install python ;;
    install_dev_zig) run_dev_env_install zig ;;
    install_dev_rust) run_dev_env_install rust ;;
    install_dev_java) run_dev_env_install java ;;
    install_dev_dotnet) run_dev_env_install dotnet ;;
    install_dev_ocaml) run_dev_env_install ocaml ;;
    install_dev_clojure) run_dev_env_install clojure ;;
    install_dev_scala) run_dev_env_install scala ;;
    install_dev_node) run_dev_env_install node ;;
    install_dev_bun) run_dev_env_install bun ;;
    install_dev_deno) run_dev_env_install deno ;;
    install_dev_php) run_dev_env_install php ;;
    install_dev_laravel) run_dev_env_install laravel ;;
    install_dev_symfony) run_dev_env_install symfony ;;
    install_dev_elixir) run_dev_env_install elixir ;;
    install_dev_phoenix) run_dev_env_install phoenix ;;
    *) return 1 ;;
  esac

  return 0
}

menu_register_action_handler menu_run_action_install
