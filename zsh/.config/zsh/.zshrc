# Add user configurations here
# Edit $ZDOTDIR/startup.zsh to customize behavior before loading zshrc
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Ignore commands that start with spaces and duplicates.
export HISTCONTROL=ignoreboth
# Don't add certain commands to the history file.
export HISTIGNORE="&:[bf]g:c:clear:history:exit:q:pwd:* --help"
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

# Use beam cursor for each new prompt
preexec() { echo -ne '\e[5 q' ;}

# Reduce ESC delay to 0.1s (default is 0.4s)
export KEYTIMEOUT=1

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

# Load a few important annexes, without Turbo
# (this is currently required for annexes)
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

### End of Zinit's installer chunk

export PATH=~/.npm-global/bin:$PATH

eval "$(zoxide init zsh)"
