# ~/.zsh/config/keybindings.zsh - Key bindings configuration

# Set vim mode
bindkey -v
export KEYTIMEOUT=40       # Switch between vi modes faster (40ms)

# Standard key bindings - keep these consistent with tmux when possible
bindkey ' ' magic-space                           # do history expansion on space
bindkey '^u' kill-line
bindkey '^U' backward-kill-line                   # ctrl + U
bindkey '^[[3;5~' kill-word                       # ctrl + Supr
bindkey '^[[3~' delete-char                       # delete
bindkey '^[[1;5C' forward-word                    # ctrl + ->
bindkey '^[[1;5D' backward-word                   # ctrl + <-
bindkey '^[[5~' beginning-of-buffer-or-history    # page up
bindkey '^[[6~' end-of-buffer-or-history          # page down
bindkey '^[[H' beginning-of-line                  # home
bindkey '^[[F' end-of-line                        # end
bindkey '^[[1~' beginning-of-line                 # alternative home
bindkey '^[[4~' end-of-line                       # alternative end

# Search bindings - consistent with tmux search
bindkey "^F" history-incremental-search-forward
bindkey "^R" history-incremental-search-backward

# Word manipulation
bindkey '^[.' insert-last-word                    # Alt-. to insert last word

# Help system
bindkey '^[h' run-help                            # Alt-h for help

# Vim-style quick escape to command mode
bindkey 'jj' vi-cmd-mode                          # Press jj to switch to command mode

# Quick line navigation similar to tmux/vim style
bindkey '^a' beginning-of-line                    # Ctrl-a to beginning (like tmux prefix)
bindkey '^e' end-of-line                          # Ctrl-e to end

# FZF integration if available
if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
    source /usr/share/fzf/completion.zsh

    # FZF styling - made consistent with tmux theme
    export FZF_DEFAULT_OPTS="--height 90% \
    --border sharp \
    --layout reverse \
    --prompt '∷ ' \
    --pointer ▶ \
    --marker ⇒"

    export FZF_CTRL_T_OPTS="$FZF_DEFAULT_OPTS"
    export FZF_ALT_C_OPTS="$FZF_DEFAULT_OPTS"
    export FZF_CTRL_R_OPTS="$FZF_DEFAULT_OPTS"

    # Use Ctrl-e for directory jumping with FZF (consistent with your tmux binding)
    zle -N fzf-cd-widget
    bindkey -M emacs '\C-e' fzf-cd-widget
    bindkey -M vicmd '\C-e' fzf-cd-widget
    bindkey -M viins '\C-e' fzf-cd-widget
fi
