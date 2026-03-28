# Elixir-family installers.

dev_env_install_elixir_runtime() {
  dev_env_install_with_mise "Elixir" erlang@latest elixir@latest
  mise x elixir -- mix local.hex --force
}

dev_env_install_elixir() {
  printf 'Installing Elixir...\n\n'
  dev_env_install_elixir_runtime
}

dev_env_install_phoenix() {
  printf 'Installing Phoenix Framework...\n\n'
  dev_env_install_elixir_runtime
  mise x elixir -- mix local.rebar --force
  mise x elixir -- mix archive.install hex phx_new --force
  printf '\nYou can now run: mix phx.new my_app\n'
}
