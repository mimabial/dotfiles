if command -v "fd" &>/dev/null; then
  # Basic fd aliases
  alias fdf='fd --type f'              # Find files only
  alias fdd='fd --type d'              # Find directories only
  alias fdh='fd --hidden'              # Include hidden files
  alias fda='fd --hidden --no-ignore'  # Include hidden and ignored files

  # Specialized searches
  alias fde='fd --extension'           # Search by extension: fde js
  alias fds='fd --type f --size'       # Search by size: fds +1m
  alias fdm='fd --type f --changed-within' # Modified within: fdm 1d
fi
