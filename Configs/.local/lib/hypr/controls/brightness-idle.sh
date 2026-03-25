#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "${script_dir}/lib/brightness.common.bash"

action="${1:-}"

brightness_idle_enabled || exit 0

case "${action}" in
  dim)
    brightnessctl -s >/dev/null 2>&1 && brightnessctl s 1% >/dev/null 2>&1 || true
    ;;
  restore)
    brightnessctl -r >/dev/null 2>&1 || true
    ;;
  *)
    exit 2
    ;;
esac
