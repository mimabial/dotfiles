#!/usr/bin/env bash

set -euo pipefail

source "$(command -v hyprshell)" || exit 1

DEV_ENV_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/dev-env" && pwd)"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/common.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/simple.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/php.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/python.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/elixir.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/ruby.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/rust.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/ocaml.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/clojure.bash"
# shellcheck source=/dev/null
source "${DEV_ENV_DIR}/scala.bash"

print_usage() {
  local runtime_list=""
  runtime_list="$(dev_env_usage_list | paste -sd'|' -)"
  printf 'Usage: hyprshell install/dev-env.sh <%s>\n' "${runtime_list}"
}

usage_error() {
  print_usage >&2
  exit 2
}

runtime="${1:-}"
case "${runtime}" in
  -h|--help)
    print_usage
    exit 0
    ;;
  "")
    usage_error
    ;;
esac

case "${runtime}" in
  ruby) dev_env_install_ruby ;;
  node) dev_env_install_simple_runtime 'Node.js' node@lts ;;
  bun) dev_env_install_simple_runtime 'Bun' bun@latest ;;
  deno) dev_env_install_simple_runtime 'Deno' deno@latest ;;
  go) dev_env_install_simple_runtime 'Go' go@latest ;;
  php) dev_env_install_php_runtime ;;
  laravel) dev_env_install_laravel ;;
  symfony) dev_env_install_symfony ;;
  python) dev_env_install_python ;;
  elixir) dev_env_install_elixir ;;
  phoenix) dev_env_install_phoenix ;;
  rust) dev_env_install_rust ;;
  java) dev_env_install_simple_runtime 'Java' java@latest ;;
  zig) dev_env_install_simple_runtime 'Zig' zig@latest zls@latest ;;
  ocaml) dev_env_install_ocaml ;;
  dotnet) dev_env_install_simple_runtime '.NET' dotnet@latest ;;
  clojure) dev_env_install_clojure ;;
  scala) dev_env_install_scala ;;
  *) usage_error ;;
esac
