#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
reload_live_theme_client() {
  local client="$1"
  local rmpc_reload="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/theme/lib/rmpc.reload.bash"

  case "${client}" in
    kitty)
      pkill -SIGUSR1 -x kitty 2>/dev/null || true
      ;;
    foot)
      # foot never re-reads its config; running windows only take colors as escape sequences.
      local -a ptys=()
      mapfile -t ptys < <(ps -o tty= --ppid "$(pgrep -d, -x foot)" 2>/dev/null)
      ((${#ptys[@]})) || return 0
      awk -F= '
        function osc(code, hex) { printf "\033]%s;#%s\033\\", code, hex }
        /^\[/ { dark = $0 == "[colors-dark]"; next }
        !dark { next }
        $1 ~ /^regular[0-7]$/ { osc("4;" substr($1, 8), $2) }
        $1 ~ /^bright[0-7]$/ { osc("4;" substr($1, 7) + 8, $2) }
        $1 == "foreground" { osc(10, $2) }
        $1 == "background" { osc(11, $2) }
        $1 == "cursor" { split($2, cursor, " "); osc(12, cursor[2]) }
        $1 == "selection-background" { osc(17, $2) }
        $1 == "selection-foreground" { osc(19, $2) }
      ' "${XDG_CACHE_HOME:-$HOME/.cache}/hypr/render/foot/colors.ini" | tee "${ptys[@]/#//dev/}" >/dev/null || true
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
