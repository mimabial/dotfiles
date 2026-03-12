#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

hypr_service_init
hypr_service_refresh_config "hypr/hypridle.conf" 0 0
systemctl --user restart hyprland-hypridle.service >/dev/null 2>&1 || true
