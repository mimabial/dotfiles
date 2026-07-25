#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# color.apply.sh - Apply generated colors to applications
#
# OVERVIEW:
#   Reload live applications after generated theme outputs are ready.
#
# USAGE:
#   source color.apply.sh
#
# DEPENDENCIES:
#   - LIB_DIR must be set (path to ~/.local/lib)
#   - print_log function from core/notify.sh

# Signal or live-reload running applications so they pick up fresh theme files.
reload_live_theme_client() {
  local client="$1"
  local tmux_config=""
  local rmpc_reload="${LIB_DIR}/hypr/theme/lib/rmpc.reload.bash"

  case "${client}" in
    kitty)
      pkill -SIGUSR1 -x kitty 2>/dev/null || true
      ;;
    tmux)
      tmux_config="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
      if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null; then
        tmux source-file "${tmux_config}" 2>/dev/null || true
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
