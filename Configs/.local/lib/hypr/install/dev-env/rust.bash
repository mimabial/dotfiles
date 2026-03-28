# Rust installer.

dev_env_install_rust() {
  printf 'Installing Rust...\n\n'
  bash -c "$(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs)" -- -y
}
