#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require system || exit 1

hypr_help_guard "Usage: hyprshell system/reset-xdg-portal
Restart the xdg-desktop-portal services (gtk, hyprland, base)." "$@"

if [[ -d /run/current-system/sw/libexec ]]; then
  lib_dir=/run/current-system/sw/libexec
else
  lib_dir=/usr/lib
fi

restart_portal_service() {
  local service_name="$1"
  local exec_name="$2"

  if systemctl --user restart "${service_name}.service" >/dev/null 2>&1; then
    return 0
  fi

  local app2unit="${HYPR_LIB_DIR}/system/app2unit.sh"
  if [[ -x "${app2unit}" ]]; then
    "${app2unit}" -t service "${lib_dir}/${exec_name}" >/dev/null 2>&1 || true
  fi
}

restart_portal_service xdg-desktop-portal-gtk xdg-desktop-portal-gtk
restart_portal_service xdg-desktop-portal-hyprland xdg-desktop-portal-hyprland
restart_portal_service xdg-desktop-portal xdg-desktop-portal
