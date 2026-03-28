# Shared helpers for development environment installers.

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  source "$(command -v hyprshell)" || exit 1
fi

dev_env_usage_list() {
  printf '%s\n' \
    ruby node bun deno go laravel symfony php python elixir phoenix rust java zig ocaml dotnet clojure scala
}

dev_env_install_with_mise() {
  local label="$1"
  shift
  local tool=""

  printf 'Installing %s...\n\n' "${label}"
  for tool in "$@"; do
    mise use --global "${tool}"
  done
}

dev_env_ensure_bashrc_path() {
  local export_line="$1"
  local bashrc_file="$HOME/.bashrc"

  touch "${bashrc_file}"
  grep -Fxq "${export_line}" "${bashrc_file}" && return 0
  printf '%s\n' "${export_line}" >>"${bashrc_file}"
}
