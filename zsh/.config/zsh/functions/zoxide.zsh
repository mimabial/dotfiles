if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"

  alias z='__zoxide_z'
  alias zz='__zoxide_zi'
fi
