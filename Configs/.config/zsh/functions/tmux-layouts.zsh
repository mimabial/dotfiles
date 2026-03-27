_tdl_fullscreen_alacritty() {
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  command -v hyprctl >/dev/null 2>&1 || return 0

  local active_fullscreen
  active_fullscreen="$(hyprctl activewindow 2>/dev/null | awk -F': ' '/^[[:space:]]*fullscreen:/ {print $2; exit}')" || return 0
  [[ "$active_fullscreen" == "1" || "$active_fullscreen" == "2" ]] && return 0

  hyprctl dispatch fullscreen 1 >/dev/null 2>&1 || true
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

tdl() {
  (($# < 1 || $# > 2)) && {
    print -u2 "Usage: tdl <ai_command> [second_ai_command]"
    print -u2 "Quote commands with spaces."
    return 1
  }

  [[ -z "${TMUX:-}" ]] && {
    print -u2 "[Error] Must start tmux to use tdl."
    return 1
  }

  local current_dir editor_pane ai_pane ai2_pane ai ai2 editor_cmd window_name
  current_dir="$PWD"
  editor_pane="${TMUX_PANE:-}"
  ai="$1"
  ai2="${2:-}"
  editor_cmd="${EDITOR:-nvim} ."
  window_name="$(basename "$current_dir" | tr '.:' '--')"

  _tdl_validate_command "$ai" "primary AI" || return 1
  _tdl_validate_command "$ai2" "secondary AI" || return 1

  [[ -z "$editor_pane" ]] && {
    print -u2 "TMUX_PANE is not set."
    return 1
  }

  tmux rename-window -t "$editor_pane" "$window_name" || return 1
  tmux split-window -v -p 15 -t "$editor_pane" -c "$current_dir" || return 1

  ai_pane="$(tmux split-window -h -p 30 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')" || return 1

  if [[ -n "$ai2" ]]; then
    ai2_pane="$(tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')" || return 1
    tmux send-keys -t "$ai2_pane" "$ai2" C-m || return 1
  fi

  tmux send-keys -t "$ai_pane" "$ai" C-m || return 1
  tmux send-keys -t "$editor_pane" "$editor_cmd" C-m || return 1
  tmux select-pane -t "$editor_pane"
  _tdl_fullscreen_alacritty
}
