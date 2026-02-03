if command -v "eza" &>/dev/null; then
  # Basic ls replacement
  alias ls='eza --icons --group-directories-first'
  alias ll='eza --icons --group-directories-first -l --git'
  alias la='eza --icons --group-directories-first -la --git'
  alias l='eza --icons --group-directories-first -lah --git'

  # Tree views
  alias tree='eza --icons --tree'
  alias lt='eza --icons --tree --level=2'
  alias lta='eza --icons --tree --level=2 -a'

  # Specialized views
  alias lS='eza --icons -1'                                    # One file per line
  alias lh='eza --icons -ldh .*'                               # Hidden files
  alias ld='eza --icons -lD'                                   # Directories only
  alias lf='eza --icons -lf --color=always | grep -v /'       # Files only
  alias lm='eza --icons -la --sort=modified'                  # Sort by modified
  alias lx='eza --icons -la --sort=extension'                 # Sort by extension
  alias lz='eza --icons -la --sort=size'                      # Sort by size
  alias lg='eza --icons -la --git-ignore'                     # Respect .gitignore
fi
