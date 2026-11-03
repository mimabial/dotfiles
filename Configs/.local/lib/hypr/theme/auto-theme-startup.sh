#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
declare -F hypr_svc_user >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/services.bash" || exit 1

state_get_into selected_color_mode selected_color_mode ""
state_get_into background_mode BACKGROUND_MODE dark
state_resolve_color_mode_into selected_color_mode "${selected_color_mode}" "${background_mode}"

warn_startup() {
  declare -F print_log >/dev/null 2>&1 && print_log -sec "auto-theme" -warn "startup" "$1"
}

if [[ "$(hypr_detect_init_system)" == "other" ]]; then
  warn_startup "no supported service manager (systemd/runit) available"
  exit 0
fi

if [[ "${selected_color_mode}" == "${STATE_COLOR_MODE_AUTO}" ]]; then
  hypr_svc_user start auto-theme || {
    warn_startup "failed to start auto-theme service"
    exit 0
  }
else
  hypr_svc_user stop auto-theme || true
fi
