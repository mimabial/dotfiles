# Add user configurations here
# Edit $ZDOTDIR/startup.zsh to customize behavior before loading zshrc
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
typeset -g ZSHRC_LOADED=1
# Ignore commands that start with spaces and consecutive duplicates.
setopt HIST_IGNORE_SPACE HIST_IGNORE_DUPS
# Don't add certain commands to the history file.
zshaddhistory() {
  emulate -L zsh
  local line=${1%%$'\n'}
  case $line in
    ("&"|bg|fg|c|clear|history|exit|q|pwd) return 1 ;;
    (*" --help") return 1 ;;
  esac
  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  Plugins 
# zinit plugins are loaded in $ZDOTDIR/startup.zsh file, see the file for more information
#  Aliases 
# Override aliases here in '$ZDOTDIR/.zshrc' (already set in .zshenv)
export EDITOR=nvim
# export EDITOR=code
# unset -f command_not_found_handler # Uncomment to prevent searching for commands not found in package manager
#  Bindings 
bindkey "^[[3~" delete-char

# Enable vi mode
bindkey -v
bindkey -M viins "^[[3~" delete-char
bindkey -M vicmd "^[[3~" delete-char

# Keep useful emacs bindings in insert mode
bindkey "^A" beginning-of-line
bindkey "^E" end-of-line
bindkey "^K" kill-line
bindkey "^U" backward-kill-line
bindkey "^W" backward-kill-word
bindkey "^Y" yank

# Change cursor shape for different vi modes
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'  # Block cursor for normal mode
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] || [[ ${KEYMAP} = '' ]] || [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'  # Beam cursor for insert mode
  fi
}
zle -N zle-keymap-select

# Start with beam cursor
echo -ne '\e[5 q'

# Use beam cursor before each command without clobbering other preexec hooks
autoload -Uz add-zsh-hook
_cursor_beam_preexec() { echo -ne '\e[5 q'; }
add-zsh-hook preexec _cursor_beam_preexec

# Reduce ESC delay to 0.1s (default is 0.4s)
export KEYTIMEOUT=1

if [[ ${ZSH_NO_PLUGINS} != "1" && ${ZSH_DEFER} != "1" ]] && ! (( ${+functions[zinit]} )); then
    ### Added by Zinit's installer
    if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
        print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
        command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
        command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
            print -P "%F{33} %F{34}Installation successful.%f%b" || \
            print -P "%F{160} The clone has failed.%f%b"
    fi

    source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
    autoload -Uz _zinit
    (( ${+_comps} )) && _comps[zinit]=_zinit
    ### End of Zinit's installer chunk
fi

typeset -gU path PATH
path=("$HOME/.npm-global/bin" $path)
