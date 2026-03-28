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
  if [[ -n "$second_agent_cmd" ]]; then
    integer right_width
    top_right_pane=""
    bottom_right_pane=""

    right_width="$(tmux display-message -p -t "$pane_id" '#{pane_width}')"
    ((right_width = right_width * 51 / 100))
    ((right_width < 1)) && right_width=1

    top_right_pane="$(tmux split-window -h -l "$right_width" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
    bottom_right_pane="$(tmux split-window -v -t "$top_right_pane" -c "$cwd" -P -F '#{pane_id}')"

    [[ "$agentless" == "1" ]] || tmux send-keys -t "$top_right_pane" "$agent_cmd" C-m
    [[ "$agentless" == "1" ]] || tmux send-keys -t "$bottom_right_pane" "$second_agent_cmd" C-m
  else
    integer top_width right_width
    tmux split-window -v -p 15 -t "$pane_id" -c "$cwd" >/dev/null
    top_width="$(tmux display-message -p -t "$pane_id" '#{pane_width}')"
    ((right_width = top_width * 40 / 100))
    ((right_width < 1)) && right_width=1
    right_pane="$(tmux split-window -h -l "$right_width" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
    [[ "$agentless" == "1" ]] || tmux send-keys -t "$right_pane" "$agent_cmd" C-m
  fi

  [[ -n "$editor_cmd" ]] && tmux send-keys -t "$pane_id" "$editor_cmd" C-m
fi
tmux select-pane -t "$pane_id"
tmux display-message "Applied dev layout to ${window_name}"
