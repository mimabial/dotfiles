#!/usr/bin/env zsh

[[ "$ZSH_PROMPT" == 1 ]] || return

# Starship requires prompt command substitution; keep plugins from disabling it.
setopt promptsubst
autoload -Uz add-zsh-hook
_promptsubst_guard() { setopt promptsubst; }
add-zsh-hook precmd _promptsubst_guard

if (( $+commands[starship] )); then
  export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship.toml"
  eval "$(starship init zsh)"
fi
