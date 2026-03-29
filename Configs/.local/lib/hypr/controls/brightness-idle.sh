#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${script_dir}/lib/brightness.common.bash"

action="${1:-}"

brightness_idle_enabled || exit 0

case "${action}" in
  dim)
    brightnessctl -s >/dev/null
    brightnessctl s 1% >/dev/null
    ;;
  restore)
    brightnessctl -r >/dev/null
    ;;
  *)
    exit 2
    ;;
esac
