#!/usr/bin/env zsh
set -euo pipefail

source "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/layouts/_common.zsh"
source "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/layouts/_dev_geometry.zsh"

_tmux_layout_require_context

dev_bottom_height_pct=20
dev_single_agent_bottom_agent_height_pct=40

: "${TMUX_DEV_SINGLE_AGENT_RIGHT_WIDTH_PCT:=$_TMUX_DEV_SINGLE_AGENT_RIGHT_WIDTH_PCT_DEFAULT}"

pane_id="$(_tmux_layout_target_pane)"
cwd="$(_tmux_layout_current_cwd "$pane_id")"
window_name="$(_tmux_layout_project_name "$cwd")"
pane_count="$(_tmux_layout_window_pane_count "$pane_id")"
dual_mode="${TMUX_LAYOUT_DUAL_MODE:-0}"
agent_cmd="${TMUX_LAYOUT_AGENT_CMD:-claude}"
second_agent_cmd="${TMUX_LAYOUT_SECOND_AGENT_CMD:-}"
focus_agent_slot="${TMUX_LAYOUT_FOCUS_AGENT_SLOT:-none}"
editor_cmd="${TMUX_LAYOUT_EDITOR_CMD:-}"
agentless="${TMUX_LAYOUT_AGENTLESS:-0}"
editor_pane="$pane_id"
primary_agent_pane=""
secondary_agent_pane=""
default_focus_pane="$pane_id"
focus_pane="$pane_id"

tmux rename-window -t "$pane_id" "$window_name"
if [[ "$pane_count" == "1" ]]; then
  if [[ "$dual_mode" == "1" ]]; then
    integer total_width left_width right_width
    dual_agent_widths=""
    total_width="$(tmux display-message -p -t "$pane_id" '#{pane_width}')"
    if dual_agent_widths="$(_tmux_dev_dual_three_pane_agent_widths "$total_width" 2>/dev/null)"; then
      left_width="${dual_agent_widths%% *}"
      right_width="${dual_agent_widths##* }"

      primary_agent_pane="$(tmux split-window -h -b -l "$left_width" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
      secondary_agent_pane="$(tmux split-window -h -l "$right_width" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
      editor_pane="$pane_id"
      default_focus_pane="$editor_pane"
    elif _tmux_dev_dual_supports_two_agents "$total_width"; then
      primary_agent_pane="$(tmux split-window -h -b -p 50 -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
      secondary_agent_pane="$pane_id"
      editor_pane=""
      default_focus_pane="$primary_agent_pane"
    else
      print -u2 "Current pane is too narrow for two agent panes."
      exit 1
    fi
  else
    integer total_width right_width
    total_width="$(tmux display-message -p -t "$pane_id" '#{pane_width}')"
    if right_width="$(_tmux_dev_single_agent_side_width "$total_width" 2>/dev/null)"; then
      primary_agent_pane="$(tmux split-window -h -l "$right_width" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
      tmux split-window -v -p "$dev_bottom_height_pct" -t "$pane_id" -c "$cwd" >/dev/null
    else
      primary_agent_pane="$(tmux split-window -v -p "$dev_single_agent_bottom_agent_height_pct" -t "$pane_id" -c "$cwd" -P -F '#{pane_id}')"
    fi

    editor_pane="$pane_id"
    default_focus_pane="$editor_pane"
  fi

  [[ "$agentless" == "1" ]] || [[ -z "$primary_agent_pane" ]] || tmux send-keys -t "$primary_agent_pane" "$agent_cmd" C-m
  [[ "$agentless" == "1" ]] || [[ -z "$secondary_agent_pane" ]] || tmux send-keys -t "$secondary_agent_pane" "$second_agent_cmd" C-m
  [[ -n "$editor_cmd" ]] && [[ -n "$editor_pane" ]] && tmux send-keys -t "$editor_pane" "$editor_cmd" C-m

  focus_pane="$default_focus_pane"
  if [[ "$focus_agent_slot" == "primary" ]] && [[ -n "$primary_agent_pane" ]]; then
    focus_pane="$primary_agent_pane"
  elif [[ "$focus_agent_slot" == "secondary" ]] && [[ -n "$secondary_agent_pane" ]]; then
    focus_pane="$secondary_agent_pane"
  fi
fi
tmux select-pane -t "$focus_pane"
tmux display-message "Applied dev layout to ${window_name}"
