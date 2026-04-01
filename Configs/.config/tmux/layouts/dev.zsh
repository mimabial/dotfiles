#!/usr/bin/env zsh
set -euo pipefail

source "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/layouts/_common.zsh"

_tmux_layout_require_context

pane_id="$(_tmux_layout_target_pane)"
cwd="$(_tmux_layout_current_cwd "$pane_id")"
window_name="$(_tmux_layout_project_name "$cwd")"
pane_count="$(_tmux_layout_window_pane_count "$pane_id")"
agent_cmd="${TMUX_LAYOUT_AGENT_CMD:-claude}"
second_agent_cmd="${TMUX_LAYOUT_SECOND_AGENT_CMD:-}"
editor_cmd="${TMUX_LAYOUT_EDITOR_CMD:-}"
agentless="${TMUX_LAYOUT_AGENTLESS:-0}"

tmux rename-window -t "$pane_id" "$window_name"
if [[ "$pane_count" == "1" ]]; then
  tmux split-window -v -p 15 -t "$pane_id" -c "$cwd" >/dev/null

  if [[ -n "$second_agent_cmd" ]]; then
    right_pane="$(tmux split-window -h -p 50 -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"

    [[ "$agentless" == "1" ]] || tmux send-keys -t "$pane_id" "$agent_cmd" C-m
    [[ "$agentless" == "1" ]] || tmux send-keys -t "$right_pane" "$second_agent_cmd" C-m
  else
    integer top_width right_width
    top_width="$(tmux display-message -p -t "$pane_id" '#{pane_width}')"
    ((right_width = top_width * 40 / 100))
    ((right_width < 1)) && right_width=1
    right_pane="$(tmux split-window -h -l "$right_width" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
    [[ "$agentless" == "1" ]] || tmux send-keys -t "$right_pane" "$agent_cmd" C-m
  fi

  if [[ -z "$second_agent_cmd" ]] && [[ -n "$editor_cmd" ]]; then
    tmux send-keys -t "$pane_id" "$editor_cmd" C-m
  fi
fi
tmux select-pane -t "$pane_id"
tmux display-message "Applied dev layout to ${window_name}"
