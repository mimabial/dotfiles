_tmux_layout_has_window() {
  local session="$1" name="$2"
  tmux list-windows -t "${session}:" -F '#{window_name}' | grep -Fxq "$name"
}

_tmux_layout_spawn_window() {
  local target="$1" name="$2" cwd="$3" cmd="${4:-}" insert_after="${5:-0}" new_target
  local -a new_window_cmd

  new_window_cmd=(
    tmux new-window -d
    -n "$name"
    -c "$cwd"
    -P -F '#{session_name}:#{window_index}'
  )

  if [[ "$insert_after" == "1" ]]; then
    new_window_cmd+=(-a -t "$target")
  else
    new_window_cmd+=(-t "$target")
  fi

  new_target="$("${new_window_cmd[@]}")" || return 1
  [[ -n "$cmd" ]] && tmux send-keys -t "$new_target" "$cmd" C-m
  print -r -- "$new_target"
}
