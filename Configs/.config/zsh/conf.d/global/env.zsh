#!/usr/bin/env zsh

typeset -gU path PATH
path=("$HOME/.local/bin" "$HOME/.local/share/npm/bin" $path)

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_DATA_DIRS="${XDG_DATA_DIRS:-$XDG_DATA_HOME:/usr/local/share:/usr/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Keep runtime files out of the mirrored config tree.
ZSH_STATE_DIR="${XDG_STATE_HOME}/zsh"
ZSH_CACHE_DIR="${XDG_CACHE_HOME}/zsh"
HISTFILE="${HISTFILE:-$ZSH_STATE_DIR/.zsh_history}"
ZSH_COMPDUMP="${ZSH_COMPDUMP:-$ZSH_CACHE_DIR/.zcompdump}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-$XDG_CACHE_HOME/python}"

_load_xdg_user_dirs() {
  local file="$XDG_CONFIG_HOME/user-dirs.dirs" line var value
  [[ -r "$file" ]] || return
  while IFS= read -r line; do
    [[ $line == XDG_*_DIR=* ]] || continue
    var=${line%%=*}
    [[ -z ${(P)var} ]] || continue
    value=${${line#*=}#\"}
    value=${value%\"}
    typeset -gx "$var"="${value//\$HOME/$HOME}"
  done < "$file"
}
_load_xdg_user_dirs
unfunction _load_xdg_user_dirs

LESSHISTFILE="${LESSHISTFILE:-/tmp/less-hist}"
PARALLEL_HOME="$XDG_CONFIG_HOME/parallel"
SCREENRC="$XDG_CONFIG_HOME/screen/screenrc"
if [[ -z "$TERMINFO_DIRS" ]]; then
  TERMINFO_DIRS=/usr/share/terminfo
  [[ -d /usr/local/share/terminfo ]] && TERMINFO_DIRS="/usr/local/share/terminfo:$TERMINFO_DIRS"
  [[ -d "$XDG_DATA_HOME/terminfo" ]] && TERMINFO_DIRS="$XDG_DATA_HOME/terminfo:$TERMINFO_DIRS"
fi
WGETRC="$XDG_CONFIG_HOME/wgetrc"
PYTHON_HISTORY="$XDG_STATE_HOME/python_history"
PYTHONHISTFILE="${PYTHONHISTFILE:-$PYTHON_HISTORY}"

export PATH XDG_CONFIG_HOME XDG_DATA_HOME XDG_DATA_DIRS XDG_STATE_HOME XDG_CACHE_HOME \
  XDG_DESKTOP_DIR XDG_DOWNLOAD_DIR XDG_TEMPLATES_DIR XDG_PUBLICSHARE_DIR \
  XDG_DOCUMENTS_DIR XDG_MUSIC_DIR XDG_PICTURES_DIR XDG_VIDEOS_DIR \
  LESSHISTFILE PARALLEL_HOME SCREENRC TERMINFO_DIRS WGETRC \
  PYTHON_HISTORY PYTHONHISTFILE HISTFILE ZSH_COMPDUMP
