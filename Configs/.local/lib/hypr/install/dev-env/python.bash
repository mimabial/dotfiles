dev_env_install_python() {
  local installer=""

  dev_env_install_with_mise "Python" python@latest
  printf '\nInstalling uv...\n\n'
  installer="$(curl -fsSL https://astral.sh/uv/install.sh)" || return 1
  sh -c "${installer}"
}
