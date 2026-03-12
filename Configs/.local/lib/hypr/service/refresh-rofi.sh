#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

hypr_service_init
hypr_service_refresh_many 0 0 \
  "rofi/config.rasi" \
  "rofi/menutree.rasi" \
  "rofi/theme.rasi" \
  "rofi/pywal16.rasi"

pkill -x rofi >/dev/null 2>&1 || true
