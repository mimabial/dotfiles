tmux() {
  if [[ "$TERM" == "alacritty" ]] || [[ -n "$ALACRITTY_SOCKET" ]]; then
    command tmux "$@"
  else
    if [[ ! -t 0 || ! -t 2 ]]; then
      print -u2 "Can't confirm close in non-interactive terminal and launch tmux in Alacritty"
      return 1
    fi

    if ! read -q "REPLY?Close terminal and launch tmux in Alacritty? [y/N] "; then
      print -u2
      return 1
    fi

    print -u2
    setsid alacritty >/dev/null 2>&1 &
    kill -TERM "$PPID"
  fi
}
