#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

hypr_service_init

shared_targets=(
  "hypr/hyprland.conf"
  "hypr/variables.conf"
  "hypr/defaults.conf"
  "hypr/env.conf"
  "hypr/dynamic.conf"
  "hypr/startup.conf"
  "hypr/finale.conf"
)

hypr_service_refresh_shared_many 0 0 "${shared_targets[@]}"

hyprctl reload >/dev/null 2>&1 || true
