#!/usr/bin/env bash
reload_live_theme_client() {
  local client="$1"
  local rmpc_reload="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/theme/lib/rmpc.reload.bash"

  case "${client}" in
    alacritty)
      # The main config is watched even when an imported palette is replaced.
      local conf="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
      [[ ! -f "${conf}" ]] || touch "${conf}"
      ;;
    kitty)
      pkill -SIGUSR1 -x kitty 2>/dev/null || true
      ;;
    cava)
      pkill -SIGUSR2 -x cava 2>/dev/null || true
      ;;
    zathura)
      local pid
      for pid in $(pgrep -x zathura); do
        gdbus call --session --dest "org.pwmt.zathura.PID-${pid}" --object-path /org/pwmt/zathura \
          --method org.pwmt.zathura.ExecuteCommand source >/dev/null 2>&1 || true
      done
      ;;
    tmux)
      if command -v tmux &>/dev/null; then
        tmux source-file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/colors.conf" 2>/dev/null || true
      fi
      ;;
    rmpc)
      [[ -r "${rmpc_reload}" ]] && bash "${rmpc_reload}"
      ;;
  esac
}

reload_hypr_shaders() {
  local reload_output=""

  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] || return 0
  if ! reload_output="$(hyprshell shaders --reload --quiet 2>&1)"; then
    print_log -sec "hyprshell" -warn "reload" "shader reload failed"
    return 1
  fi

  if grep -qi "error" <<<"${reload_output}"; then
    print_log -sec "hyprshell" -warn "reload" "shader reload reported errors"
    return 1
  fi

  [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -sec "hyprshell" -stat "reload" "shaders"
  return 0
}

post_updates() {
  reload_hypr_shaders
}
