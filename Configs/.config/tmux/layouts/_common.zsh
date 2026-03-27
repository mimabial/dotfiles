#!/usr/bin/env zsh
set -euo pipefail

_tmux_layout_require_context() {
  _tmux_layout_target_pane >/dev/null || {
    print -u2 "This layout must be launched from inside tmux."
    return 1
  }
}

_tmux_layout_target_pane() {
  local pane_id="${TMUX_PANE:-}"
  [[ -n "$pane_id" ]] || pane_id="$(tmux display-message -p '#{pane_id}' 2>/dev/null)"
  [[ -n "$pane_id" ]] || return 1
  print -r -- "$pane_id"
}

_tmux_layout_current_cwd() {
  local pane_id="$1"
  tmux display-message -p -t "$pane_id" '#{pane_current_path}'
}

_tmux_layout_current_session() {
  local pane_id="$1"
  tmux display-message -p -t "$pane_id" '#{session_name}'
}

_tmux_layout_project_name() {
  local cwd="$1"
  basename "$cwd" | tr '.:' '--'
}

_tmux_layout_window_pane_count() {
  local pane_id="$1"
  tmux display-message -p -t "$pane_id" '#{window_panes}'
}

_tmux_layout_ensure_workspace_panes() {
  local pane_id="$1" cwd="$2" pane_count
  pane_count="$(_tmux_layout_window_pane_count "$pane_id")"
  [[ "$pane_count" == "1" ]] || return 0

  tmux split-window -v -p 15 -t "$pane_id" -c "$cwd" >/dev/null
  tmux split-window -h -p 30 -t "$pane_id" -c "$cwd" >/dev/null
  tmux select-pane -t "$pane_id"
}

_tmux_layout_rightmost_pane() {
  local target="$1"
  tmux list-panes -t "$target" -F '#{pane_id} #{pane_left}' \
    | sort -k2,2n \
    | tail -n1 \
    | awk '{print $1}'
}

_tmux_layout_has_window() {
  local session="$1" name="$2"
  tmux list-windows -t "${session}:" -F '#{window_name}' | grep -Fxq "$name"
}

_tmux_layout_ensure_window() {
  local session="$1" name="$2" cwd="$3" cmd="${4:-}"
  local session_target="${session}:"
  _tmux_layout_has_window "$session" "$name" && return 0

  tmux new-window -d -t "$session_target" -n "$name" -c "$cwd"
  [[ -n "$cmd" ]] && tmux send-keys -t "$session:$name" "$cmd" C-m
  return 0
}
