#!/usr/bin/env zsh

# shellcheck disable=SC1091
if ! source "$ZDOTDIR/conf.d/global/env.zsh"; then
  print -u2 "Could not source $ZDOTDIR/conf.d/global/env.zsh"
  return 1
fi

if [[ $- == *i* && -r "$ZDOTDIR/conf.d/global/terminal.zsh" ]]; then
  source "$ZDOTDIR/conf.d/global/terminal.zsh" || print -u2 "Could not source $ZDOTDIR/conf.d/global/terminal.zsh"
fi
