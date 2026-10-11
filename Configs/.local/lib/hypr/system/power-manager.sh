#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

power_runtime_dir="$HYPR_RUNTIME_DIR/power-manager"

SECONDS_PER_MINUTE=60
IDLE_ARM_ELAPSED_SECONDS=60

source "${BASH_SOURCE[0]%/*}/power/settings.bash"
source "${BASH_SOURCE[0]%/*}/power/idle-actions.bash"
source "${BASH_SOURCE[0]%/*}/power/session-actions.bash"

case "${1:-}" in
  state) power_source_state ;;
  enabled) power_manager_enabled ;;
  apply-profile) power_apply_profile ;;
  idle-plan) power_idle_plan ;;
  idle-arm) power_arm_idle ;;
  idle-rearm) power_rearm_idle ;;
  idle-cancel) power_cancel_idle ;;
  idle-legacy) power_manager_enabled || hyprshell session/suspend.sh ;;
  idle-wait) power_wait_idle "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
  lid-action) power_lid_action ;;
  perform) power_perform_action "${2:-}" "${3:-}" ;;
  -h|--help) printf 'Usage: hyprshell system/power-manager <state|enabled|apply-profile|idle-plan|idle-arm|idle-rearm|idle-cancel|idle-legacy|idle-wait TOKEN DELAY ACTION PID|lid-action|perform ACTION [--locked]>\n' ;;
  *) exit 2 ;;
esac
