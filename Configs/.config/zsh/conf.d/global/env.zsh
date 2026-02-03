#!/usr/bin/env zsh

#! ██████╗░░█████╗░  ███╗░░██╗░█████╗░████████╗  ███████╗██████╗░██╗████████╗
#! ██╔══██╗██╔══██╗  ████╗░██║██╔══██╗╚══██╔══╝  ██╔════╝██╔══██╗██║╚══██╔══╝
#! ██║░░██║██║░░██║  ██╔██╗██║██║░░██║░░░██║░░░  █████╗░░██║░░██║██║░░░██║░░░
#! ██║░░██║██║░░██║  ██║╚████║██║░░██║░░░██║░░░  ██╔══╝░░██║░░██║██║░░░██║░░░
#! ██████╔╝╚█████╔╝  ██║░╚███║╚█████╔╝░░░██║░░░  ███████╗██████╔╝██║░░░██║░░░
#! ╚═════╝░░╚════╝░  ╚═╝░░╚══╝░╚════╝░░░░╚═╝░░░  ╚══════╝╚═════╝░╚═╝░░░╚═╝░░░

# If users used UWSM, uwsm will override any variables set anywhere in your shell configurations

# Basic PATH prepending (user local bin)
typeset -gU path PATH
path=("$HOME/.local/bin" $path)

# XDG Base Directory Specification variables with defaults
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_DATA_DIRS="${XDG_DATA_DIRS:-$XDG_DATA_HOME:/usr/local/share:/usr/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Zsh runtime locations (keep history/compdump out of dotfiles)
ZSH_STATE_DIR="${XDG_STATE_HOME}/zsh"
ZSH_CACHE_DIR="${XDG_CACHE_HOME}/zsh"
HISTFILE="${HISTFILE:-$ZSH_STATE_DIR/.zsh_history}"
ZSH_COMPDUMP="${ZSH_COMPDUMP:-$ZSH_CACHE_DIR/.zcompdump}"

# XDG User Directories (from config file; avoids external calls)
_load_xdg_user_dirs() {
  local user_dirs_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
  local line var val
  [[ -r "$user_dirs_file" ]] || return 0

  while IFS= read -r line; do
    [[ $line == XDG_*_DIR=* ]] || continue
    var=${line%%=*}
    [[ -z ${(P)var} ]] || continue
    val=${line#*=}
    val=${val#\"}
    val=${val%\"}
    val=${val//\$HOME/$HOME}
    typeset -gx "$var"="$val"
  done < "$user_dirs_file"
}
_load_xdg_user_dirs
unset -f _load_xdg_user_dirs

# Less history file location
LESSHISTFILE="${LESSHISTFILE:-/tmp/less-hist}"

# Application config files
PARALLEL_HOME="$XDG_CONFIG_HOME/parallel"
SCREENRC="$XDG_CONFIG_HOME/screen/screenrc"
if [[ -z "$TERMINFO_DIRS" ]]; then
  TERMINFO_DIRS="/usr/share/terminfo"
  [[ -d /usr/local/share/terminfo ]] && TERMINFO_DIRS="/usr/local/share/terminfo:$TERMINFO_DIRS"
  [[ -d "$XDG_DATA_HOME/terminfo" ]] && TERMINFO_DIRS="$XDG_DATA_HOME/terminfo:$TERMINFO_DIRS"
fi
WGETRC="${XDG_CONFIG_HOME}/wgetrc"
PYTHON_HISTORY="$XDG_STATE_HOME/python_history"
PYTHONHISTFILE="${PYTHONHISTFILE:-$PYTHON_HISTORY}"

# Compositor Configuration
export HYPRLAND_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"

QT_STYLE_OVERRIDE=kvantum

# Export all variables
export PATH \
  XDG_CONFIG_HOME XDG_DATA_HOME XDG_DATA_DIRS XDG_STATE_HOME XDG_CACHE_HOME \
  XDG_DESKTOP_DIR XDG_DOWNLOAD_DIR XDG_TEMPLATES_DIR XDG_PUBLICSHARE_DIR \
  XDG_DOCUMENTS_DIR XDG_MUSIC_DIR XDG_PICTURES_DIR XDG_VIDEOS_DIR \
  LESSHISTFILE PARALLEL_HOME SCREENRC TERMINFO_DIRS WGETRC \
  PYTHON_HISTORY PYTHONHISTFILE QT_STYLE_OVERRIDE \
  HISTFILE ZSH_COMPDUMP
