if command -v "rg" &>/dev/null; then
  alias rg='rg --smart-case --hidden'
  alias rga='rg --smart-case --hidden --no-ignore'
  alias rgl='rg --smart-case --hidden --files-with-matches'
  alias rgf='rg --smart-case --hidden --files'
  alias rgt='rg --smart-case --hidden --type-list'
  alias rgjs='rg --smart-case --hidden --type js'
  alias rgpy='rg --smart-case --hidden --type py'
  alias rgrs='rg --smart-case --hidden --type rust'
  alias rgmd='rg --smart-case --hidden --type markdown'
  alias rgjson='rg --smart-case --hidden --type json'

  alias rgc='rg --smart-case --hidden --count'
  alias rgi='rg --ignore-case --hidden'
  alias rgw='rg --smart-case --hidden --word-regexp'
fi
