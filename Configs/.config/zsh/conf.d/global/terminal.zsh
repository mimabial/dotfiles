#!/usr/bin/env zsh

_load_functions() {
  local file
  for file in "$ZDOTDIR/functions/"*.zsh(N); do source "$file"; done
}

_load_completions() {
  local file
  for file in "$ZDOTDIR/completions/"*.zsh(N); do source "$file"; done
}

# Keep the generated completion aligned with its two source files without
# invoking its Python option parser on cache hits.
_refresh_hyprshell_completion() {
  (( $+commands[hyprshell] )) || return
  zmodload -F zsh/stat b:zstat 2>/dev/null || return
  local snap="$ZDOTDIR/completions/hyprshell.zsh"
  local lib="${LIB_DIR:-$HOME/.local/lib}/hypr/shell/lib" f
  local -a stat
  local newest=0
  for f in "$lib/hyprshell.completion.bash" "$lib/hyprshell.commands.bash"; do
    [[ -r $f ]] && zstat -A stat +mtime "$f" 2>/dev/null && (( stat[1] > newest )) && newest=$stat[1]
  done
  (( newest )) || return
  [[ -r $snap ]] && zstat -A stat +mtime "$snap" 2>/dev/null && (( stat[1] >= newest )) && return
  hyprshell --completions zsh >| "$snap.tmp" 2>/dev/null && mv -f "$snap.tmp" "$snap" || rm -f "$snap.tmp"
}

_init_zinit() {
  ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
  if [[ ! -d "$ZINIT_HOME/.git" ]]; then
    (( $+commands[git] )) || { print -u2 'zinit: git not found'; return 1; }
    mkdir -p "$ZINIT_HOME:h"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" || return
  fi
  [[ -r "$ZINIT_HOME/zinit.zsh" ]] || { print -u2 "zinit: missing $ZINIT_HOME/zinit.zsh"; return 1; }
  source "$ZINIT_HOME/zinit.zsh"
  zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust
  zinit snippet OMZL::git.zsh
  zinit snippet OMZP::git
  zinit light chrissicool/zsh-256color
  zinit light zsh-users/zsh-autosuggestions
  zinit light zsh-users/zsh-syntax-highlighting
  [[ -r "$ZDOTDIR/plugins.zsh" ]] && source "$ZDOTDIR/plugins.zsh"
}

_load_compinit() {
  autoload -Uz compinit _zinit
  (( ${+_comps} )) && _comps[zinit]=_zinit
  setopt EXTENDED_GLOB
  local dump="${ZSH_COMPDUMP:-$ZDOTDIR/.zcompdump}"
  if [[ ! -e $dump || -n ${dump}(#qN.mh+${ZSH_COMPINIT_CHECK:-1}) ]]; then
    compinit -d "$dump"
  else
    compinit -C -d "$dump"
  fi
  _comp_options+=(globdots)
}

_load_prompt() {
  [[ -r "$ZDOTDIR/conf.d/global/prompt.zsh" ]] && source "$ZDOTDIR/conf.d/global/prompt.zsh"
}

_defer_zinit_after_prompt_before_input() {
  [[ -z ${_ZSH_DEFERRED_INIT_DONE-} ]] || { zle -D zle-line-init 2>/dev/null; return; }
  typeset -g _ZSH_DEFERRED_INIT_DONE=1
  zle -D zle-line-init 2>/dev/null
  _init_zinit
  fpath=("$ZDOTDIR/completions" $fpath)
  _load_compinit
  _load_functions
  _refresh_hyprshell_completion
  _load_completions
  (( ${+functions[_zsh_autosuggest_start]} )) && _zsh_autosuggest_start
}

_load_deferred_plugin_system() {
  [[ "$ZSH_DEFER" == 1 ]] || { unfunction _load_deferred_plugin_system; return; }
  if [[ -n ${DEFER_ZINIT_LOAD-} ]]; then
    unset DEFER_ZINIT_LOAD
    zle -N zle-line-init _defer_zinit_after_prompt_before_input
  fi
  bindkey '\e[H' beginning-of-line
  bindkey '\e[F' end-of-line
}

ZSH_DEFER=1
ZSH_PROMPT=1
ZSH_NO_PLUGINS=0
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
mkdir -p "$ZSH_STATE_DIR" "$ZSH_CACHE_DIR"

HISTFILE=${HISTFILE:-$ZDOTDIR/.zsh_history}
if [[ -f $HOME/.zsh_history && ! -f $HISTFILE ]]; then
  print -u2 "Move $HOME/.zsh_history to $HISTFILE to preserve it"
fi
HISTSIZE=10000
SAVEHIST=10000
# Concurrent shells append under a lock instead of rewriting history at exit.
setopt INC_APPEND_HISTORY HIST_FCNTL_LOCK
export HISTFILE ZSH_AUTOSUGGEST_STRATEGY HISTSIZE SAVEHIST

PM_COMMAND=(hyprshell pm)

if [[ $ZSH_NO_PLUGINS != 1 ]]; then
  if [[ $ZSH_DEFER == 1 ]]; then
    typeset -g DEFER_ZINIT_LOAD=1
    _load_deferred_plugin_system
    _load_prompt
  else
    _init_zinit
    fpath=("$ZDOTDIR/completions" $fpath)
    _load_compinit
    _load_prompt
    _load_functions
    _refresh_hyprshell_completion
    _load_completions
  fi
fi

__package_manager() { "${PM_COMMAND[@]}" "$@"; }

alias cl='clear' \
  hs='hyprshell' \
  in='__package_manager install' \
  un='__package_manager remove' \
  up='__package_manager upgrade' \
  pl='__package_manager search installed' \
  pa='__package_manager search all' \
  vc='vscodium' \
  vi='nvim' \
  ..='cd ..' \
  ...='cd ../..' \
  .3='cd ../../..' \
  .4='cd ../../../..' \
  .5='cd ../../../../..' \
  mvi='mv -i' \
  rmi='rm -i' \
  rmI='rm -I' \
  mkdir='mkdir -p'
