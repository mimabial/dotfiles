if command -v "eza" &>/dev/null; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza --icons --group-directories-first -l --git'
  alias la='eza --icons --group-directories-first -la --git'
  alias l='eza --icons --group-directories-first -lah --git'

  alias tree='eza --icons --tree'
  alias lt='eza --icons --tree --level=2'
  alias lta='eza --icons --tree --level=2 -a'

  alias lS='eza --icons -1'
  alias lh='eza --icons -ldh .*'
  alias ld='eza --icons -lD'
  alias lf='eza --icons -lf --color=always | grep -v /'
  alias lm='eza --icons -la --sort=modified'
  alias lx='eza --icons -la --sort=extension'
  alias lz='eza --icons -la --sort=size'
  alias lg='eza --icons -la --git-ignore'
else
  alias ls='ls --color=auto'
  alias l='ls -alFtr'
  alias ll='ls -alF'
  alias la='ls -A'
fi
