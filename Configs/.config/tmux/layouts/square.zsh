#!/usr/bin/env zsh
set -euo pipefail

source "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/layouts/_common.zsh"
source "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/layouts/_dev_geometry.zsh"

_tmux_layout_require_context

square_split_pct=50

pane_id="$(_tmux_layout_target_pane)"
cwd="$(_tmux_layout_current_cwd "$pane_id")"
window_name="$(_tmux_layout_project_name "$cwd")"
pane_count="$(_tmux_layout_window_pane_count "$pane_id")"
agent_cmd="${TMUX_LAYOUT_AGENT_CMD:-opencode}"
editor_cmd="${TMUX_LAYOUT_EDITOR_CMD:-}"
diff_cmd="${TMUX_LAYOUT_DIFF_CMD:-$(_tmux_layout_diff_watch_command)}"

tmux rename-window -t "$pane_id" "$window_name"
if [[ "$pane_count" == "1" ]]; then
  integer total_width
  total_width="$(tmux display-message -p -t "$pane_id" '#{pane_width}')"
  _tmux_dev_dual_supports_two_agents "$total_width" || {
    print -u2 "Current pane is too narrow for a square layout."
    exit 1
  }

  terminal_pane="$(tmux split-window -v -p "$square_split_pct" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
  diff_pane="$(tmux split-window -h -p "$square_split_pct" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
  agent_pane="$(tmux split-window -h -p "$square_split_pct" -t "$terminal_pane" -c "$cwd" -P -F '#{pane_id}')"

  [[ -z "$editor_cmd" ]] || tmux send-keys -t "$pane_id" "$editor_cmd" C-m
  [[ -z "$diff_cmd" ]] || tmux send-keys -t "$diff_pane" "$diff_cmd" C-m
  [[ -z "$agent_cmd" ]] || tmux send-keys -t "$agent_pane" "$agent_cmd" C-m
fi
tmux select-pane -t "$pane_id"
tmux display-message "Applied square layout to ${window_name}"
