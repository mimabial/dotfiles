# Python installer.

dev_env_install_python() {
  printf 'Installing Python...\n\n'
  dev_env_install_with_mise "Python" python@latest
  printf '\nInstalling uv...\n\n'
  curl -fsSL https://astral.sh/uv/install.sh | sh
}
