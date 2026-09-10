if command -v "fd" &>/dev/null; then
  alias fdf='fd --type f'
  alias fdd='fd --type d'
  alias fdh='fd --hidden'
  alias fda='fd --hidden --no-ignore'
  alias fde='fd --extension'
  alias fds='fd --type f --size'
  alias fdm='fd --type f --changed-within'
fi
