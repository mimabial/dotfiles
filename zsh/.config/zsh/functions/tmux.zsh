tmux() {
  if [[ "$TERM" == "alacritty" ]] || [[ -n "$ALACRITTY_SOCKET" ]]; then
    command tmux "$@"
  else
    setsid alacritty >/dev/null 2>&1 &
    kill -TERM $PPID
  fi
}
