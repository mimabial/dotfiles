# Additional Zinit Plugins
# This file loads extra plugins beyond the core ones in terminal.zsh
# Add your custom plugins here

# Plugin: sudo (oh-my-zsh)
# Adds sudo functionality and aliases
zinit snippet OMZP::sudo

# Plugin: history-search-multi-word
# Allows searching your command history by multiple words, making it easier to find previous commands.
zinit load zdharma-continuum/history-search-multi-word

# Snippet: Useful Zsh functions
# Loads a collection of handy Zsh functions from a Gist.
zinit snippet https://gist.githubusercontent.com/hightemp/5071909/raw/

# Plugin: z (rupa/z)
# Enables quick directory jumping based on your usage history.
# just like zoxide, but for zsh
# zinit light rupa/z

# Plugin: zsh-completions
# Adds many extra tab completions for Zsh, improving command-line productivity.
zinit light zsh-users/zsh-completions

# Plugin: zsh-history-substring-search
# Lets you search your history for commands containing a substring, similar to Oh My Zsh.
zinit light zsh-users/zsh-history-substring-search

# Plugin: zsh-autopair
# Automatically inserts matching brackets, quotes, etc., as you type.
zinit light hlissner/zsh-autopair

# Plugin: fzf-tab
# Enhances tab completion with fzf-powered fuzzy search and a better UI.
zinit light Aloxaf/fzf-tab

# Plugin: alias-tips
# Shows tips for using defined aliases when you type commands, helping you learn and use your aliases.
zinit light djui/alias-tips

# Deferred loading for non-essential plugins (improves startup time)
zinit wait lucid light-mode for \
    "OMZP::colored-man-pages" \
    "OMZP::extract"
