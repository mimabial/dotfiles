function rmpc() {
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

  "${config_home}/rmpc/lib/launch" "$@"
}
