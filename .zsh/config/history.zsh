# ~/.zsh/config/history.zsh - History configuration

# History file configuration
HISTFILE=~/.zsh_history
HISTSIZE=10000                     # Increased history size
SAVEHIST=20000                     # Increased saved history

# History options
setopt hist_expire_dups_first      # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_dups            # ignore duplicated commands history list
setopt hist_ignore_space           # ignore commands that start with space
setopt hist_verify                 # show command with history expansion to user before running it

# Force zsh to show the complete history
alias history="history 0"

# Configure `time` format
TIMEFMT=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'
