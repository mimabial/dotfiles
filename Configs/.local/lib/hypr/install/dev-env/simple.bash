# Install runtimes that only require global mise tools.

dev_env_install_simple_runtime() {
  local label="$1"
  shift
  dev_env_install_with_mise "${label}" "$@"
}
