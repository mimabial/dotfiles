#!/usr/bin/env zsh

for file in "${ZDOTDIR:-$HOME/.config/zsh}/conf.d/"*.zsh(N); do
  source "$file"
done
