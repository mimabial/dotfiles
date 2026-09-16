tmux_f() {
  if [[ "$TERM" == foot* ]]; then
    command tmux "$@"
  else
    if [[ ! -t 0 || ! -t 2 ]]; then
      print -u2 "Can't confirm close in non-interactive terminal and launch tmux in foot"
      return 1
    fi

    if ! read -q "REPLY?Close terminal and launch tmux in foot? [y/N] "; then
      print -u2
      return 1
    fi

    print -u2
    setsid foot >/dev/null 2>&1 &
    kill -TERM "$PPID"
  fi
}

copy-line-to-clipboard() {
  print -rn -- "$BUFFER" | "$HOME/.config/tmux/scripts/tmux-copy"
  zle -M "Line copied to clipboard!"
}
zle -N copy-line-to-clipboard
bindkey -M viins '^X^Y' copy-line-to-clipboard
bindkey -M vicmd '^X^Y' copy-line-to-clipboard
