#!/usr/bin/env zsh
set -euo pipefail

source "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/layouts/_common.zsh"

_tmux_layout_require_context

swarm_max_panes=4

pane_id="$(_tmux_layout_target_pane)"
cwd="$(_tmux_layout_current_cwd "$pane_id")"
window_name="$(_tmux_layout_project_name "$cwd")"
pane_count="$(_tmux_layout_window_pane_count "$pane_id")"
integer target_panes="${TMUX_LAYOUT_SWARM_PANES:-$swarm_max_panes}"

(( target_panes >= 1 && target_panes <= swarm_max_panes )) || {
  print -u2 "Swarm pane count must be between 1 and ${swarm_max_panes}."
  exit 1
}

tmux rename-window -t "$pane_id" "$window_name"
if [[ "$pane_count" == "1" ]]; then
  typeset -a panes=("$pane_id")
  local new_pane cmd_var cmd
  integer index

  while (( ${#panes[@]} < target_panes )); do
    new_pane="$(tmux split-window -h -t "${panes[-1]}" -c "$cwd" -P -F '#{pane_id}')" || {
      print -u2 "No room for ${target_panes} panes in this window."
      exit 1
    }
    panes+=("$new_pane")
    tmux select-layout -t "${panes[1]}" tiled >/dev/null
  done

  for index in {1..${#panes[@]}}; do
    cmd_var="TMUX_LAYOUT_SWARM_CMD_${index}"
    cmd="${(P)cmd_var:-}"
    [[ -z "$cmd" ]] || tmux send-keys -t "${panes[$index]}" "$cmd" C-m
  done
fi
tmux select-pane -t "$pane_id"
tmux display-message "Applied swarm layout to ${window_name}"
