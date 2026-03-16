#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

[[ "$#" -eq 0 ]] || {
  printf 'Usage: hyprshell service/refresh-hyprsunset.sh\n' >&2
  exit 1
}

exec "${script_dir}/restart-hyprsunset.sh"
