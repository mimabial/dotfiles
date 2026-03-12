#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

hypr_service_init
if hypr_service_has_template "hypr/hyprsunset.conf"; then
  hypr_service_refresh_config "hypr/hyprsunset.conf" 0 0
fi
hyprshell service/restart-hyprsunset.sh
