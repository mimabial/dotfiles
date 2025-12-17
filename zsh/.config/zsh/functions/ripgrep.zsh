if command -v "rg" &>/dev/null; then
  # Ripgrep aliases
  alias rg='rg --smart-case --hidden'                    # Smart case, include hidden
  alias rga='rg --smart-case --hidden --no-ignore'      # Include ignored files
  alias rgl='rg --smart-case --hidden --files-with-matches'  # Show only filenames
  alias rgf='rg --smart-case --hidden --files'          # List files that would be searched
  alias rgt='rg --smart-case --hidden --type-list'      # Show supported file types

  # Search specific file types
  alias rgjs='rg --smart-case --hidden --type js'
  alias rgpy='rg --smart-case --hidden --type py'
  alias rgrs='rg --smart-case --hidden --type rust'
  alias rgmd='rg --smart-case --hidden --type markdown'
  alias rgjson='rg --smart-case --hidden --type json'

  # Advanced searches
  alias rgc='rg --smart-case --hidden --count'          # Count matches per file
  alias rgi='rg --ignore-case --hidden'                 # Case insensitive
  alias rgw='rg --smart-case --hidden --word-regexp'    # Match whole words only
fi
