#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

hypr_service_init
hypr_service_refresh_many 0 0 \
  "waybar/config.jsonc" \
  "waybar/style.css"
hyprshell service/restart-waybar.sh
