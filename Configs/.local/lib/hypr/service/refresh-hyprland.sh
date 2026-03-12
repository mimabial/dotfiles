#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

hypr_service_init

refresh_targets=(
  "hypr/hyprland.conf"
  "hypr/windowrules.conf"
  "hypr/keybindings.conf"
  "hypr/monitors.conf"
  "hypr/userprefs.conf"
  "hypr/userfonts.conf"
  "hypr/workflows.conf"
  "hypr/workspaces.conf"
)

hypr_service_refresh_many 0 0 "${refresh_targets[@]}"

hyprctl reload >/dev/null 2>&1 || true
