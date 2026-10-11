#!/usr/bin/env bash

set -euo pipefail

DEV_ENV_DIR="${BASH_SOURCE[0]%/*}/dev-env"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/tool-installation.bash"

DEV_ENV_RUNTIMES=(
  "ruby|ruby|dev_env_install_ruby"
  "node||dev_env_install_with_mise Node.js node@lts"
  "bun||dev_env_install_with_mise Bun bun@latest"
  "deno||dev_env_install_with_mise Deno deno@latest"
  "go||dev_env_install_with_mise Go go@latest"
  "laravel|php|dev_env_install_laravel"
  "symfony|php|dev_env_install_symfony"
  "php|php|dev_env_install_php_runtime"
  "python|python|dev_env_install_python"
  "elixir|elixir|dev_env_install_elixir"
  "phoenix|elixir|dev_env_install_phoenix"
  "rust|rust|dev_env_install_rust"
  "java||dev_env_install_with_mise Java java@latest"
  "zig||dev_env_install_with_mise Zig zig@latest zls@latest"
  "ocaml|ocaml|dev_env_install_ocaml"
  "dotnet||dev_env_install_with_mise .NET dotnet@latest"
  "clojure|clojure|dev_env_install_clojure"
  "scala|scala|dev_env_install_scala"
)

print_usage() {
  local runtime_list=""
  runtime_list="$(printf '%s\n' "${DEV_ENV_RUNTIMES[@]%%|*}" | paste -sd'|' -)"
  printf 'Usage: hyprshell install/dev-env.sh <%s>\n' "${runtime_list}"
}

runtime="${1:-}"
if [[ "${runtime}" == -h || "${runtime}" == --help ]]; then
  print_usage
  exit 0
fi

for entry in "${DEV_ENV_RUNTIMES[@]}"; do
  IFS='|' read -r name module command <<<"${entry}"
  [[ "${name}" == "${runtime}" ]] || continue
  # shellcheck source=/dev/null
  [[ -z "${module}" ]] || source "${DEV_ENV_DIR}/${module}.bash"
  read -r -a install_command <<<"${command}"
  "${install_command[@]}"
  exit
done

print_usage >&2
exit 2
