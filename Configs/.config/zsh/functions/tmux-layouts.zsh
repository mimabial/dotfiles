_tdl_fullscreen_window() {
  command -v hyprctl >/dev/null 2>&1 || return 0

  local active_fullscreen
  active_fullscreen="$(hyprctl activewindow 2>/dev/null | awk -F': ' '/^[[:space:]]*fullscreen:/ {print $2; exit}')" || return 0
  [[ "$active_fullscreen" != "0" ]] && return 0

  hyprctl dispatch fullscreen 0 >/dev/null 2>&1 || true
}

_tdl_validate_command() {
  local cmd="$1" label="$2" binary
  [[ -n "$cmd" ]] || return 0

  binary="${cmd%%[[:space:]]*}"
  [[ -n "$binary" ]] || {
    print -u2 "Invalid ${label} command."
    return 1
  }

  command -v -- "$binary" >/dev/null 2>&1 || {
    print -u2 "[Error] Unknown ${label} command: $binary"
    return 1
  }
}

_tdl_window_exists() {
  local session="$1" name="$2"
  tmux list-windows -t "${session}:" -F '#{window_name}' | grep -Fxq "$name"
}

_tdl_ensure_aux_window() {
  local after_target="$1" name="$2" cwd="$3" cmd="${4:-}"
  local session new_target

  session="${after_target%%:*}"
  _tdl_window_exists "$session" "$name" && {
    print -r -- "$after_target"
    return 0
  }

  new_target="$(tmux new-window -d -a -t "$after_target" -n "$name" -c "$cwd" -P -F '#{session_name}:#{window_index}')" || return 1
  [[ -n "$cmd" ]] && tmux send-keys -t "${session}:$name" "$cmd" C-m
  print -r -- "$new_target"
}

tdl() {
  local open_git=0 open_docker=0

  while (($#)); do
    case "$1" in
      --git)
        open_git=1
        shift
        ;;
      --docker)
        open_docker=1
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        print -u2 "Unknown option: $1"
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  (($# > 2)) && {
    print -u2 "Usage: tdl [--git] [--docker] [ai_command] [second_ai_command]"
    print -u2 "Quote commands with spaces when provided."
    return 1
  }

  [[ -z "${TMUX:-}" ]] && {
    print -u2 "[Error] Must start tmux to use tdl."
    return 1
  }

  local layout_runner ai ai2 editor_cmd current_dir current_target git_cmd docker_cmd agentless
  ai="${1:-}"
  ai2="${2:-}"
  editor_cmd="${EDITOR:-nvim} ."
  current_dir="$PWD"
  layout_runner="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts/tmux-layout"
  agentless=0

  if [[ -z "$ai" ]]; then
    agentless=1
  else
    _tdl_validate_command "$ai" "primary AI" || return 1
    _tdl_validate_command "$ai2" "secondary AI" || return 1
  fi

  [[ -x "$layout_runner" ]] || {
    print -u2 "tmux layout runner is not available."
    return 1
  }

  TMUX_LAYOUT_AGENTLESS="$agentless" \
  TMUX_LAYOUT_AGENT_CMD="$ai" \
  TMUX_LAYOUT_SECOND_AGENT_CMD="$ai2" \
  TMUX_LAYOUT_EDITOR_CMD="$editor_cmd" \
  "$layout_runner" dev || return 1

  current_target="$(tmux display-message -p -t "${TMUX_PANE:-}" '#{session_name}:#{window_index}')" || return 1

  if (( open_git )); then
    git_cmd=""
    command -v lazygit >/dev/null 2>&1 && git_cmd="lazygit"
    current_target="$(_tdl_ensure_aux_window "$current_target" git "$current_dir" "$git_cmd")" || return 1
  fi

  if (( open_docker )); then
    docker_cmd=""
    command -v lazydocker >/dev/null 2>&1 && docker_cmd="lazydocker"
    current_target="$(_tdl_ensure_aux_window "$current_target" docker "$current_dir" "$docker_cmd")" || return 1
  fi

  _tdl_fullscreen_window
}
