dev_env_install_rust() {
  local installer=""

  printf 'Installing Rust...\n\n'
  installer="$(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs)" || return 1
  bash -c "${installer}" -- -y
}
