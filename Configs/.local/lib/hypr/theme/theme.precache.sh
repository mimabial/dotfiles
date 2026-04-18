#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# theme.precache.sh - Background prewarmer for adjacent theme color caches.
#
# Purpose:
#   Precompute cache-only theme-mode pywal outputs for likely next switches
#   without touching the live UI path.

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
hypr_runtime_load_state || exit 1

COLOR_SET_SCRIPT="${LIB_DIR}/hypr/theme/color-sync.sh"
THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"
THEME_PRECACHE_LOCK="$(hypr_lock_path theme_precache)"

exec 204>"${THEME_PRECACHE_LOCK}"
flock -n 204 || exit 0

theme_precache_wait_for_idle_switch() {
  exec 205>"${THEME_SWITCH_LOCK}"
  flock 205
  flock -u 205
  exec 205>&-
}

theme_precache_run_low_prio() {
  if command -v ionice &>/dev/null; then
    ionice -c 3 nice -n 10 "$@"
  else
    nice -n 10 "$@"
  fi
}

theme_precache_resolved_variant() {
  if declare -F state_get_color_variant >/dev/null 2>&1; then
    state_get_color_variant
    return
  fi
  printf '%s\n' "dark"
}

theme_precache_one() {
  local theme_name="$1"
  local variant="$2"

  [[ -n "${theme_name}" ]] || return 0
  [[ -d "${HYPR_CONFIG_HOME}/themes/${theme_name}" ]] || return 0

  theme_precache_wait_for_idle_switch

  theme_precache_run_low_prio env \
    HYPR_WAL_CACHE_ONLY=1 \
    HYPR_WAL_CACHE_CLEANUP=0 \
    HYPR_WAL_CACHE_PRUNE=0 \
    HYPR_WAL_MODE_OVERRIDE="${variant}" \
    HYPR_THEME_OVERRIDE="${theme_name}" \
    HYPR_COLOR_MODE_OVERRIDE=0 \
    bash "${COLOR_SET_SCRIPT}" >/dev/null 2>&1 || true
}

main() {
  local variant
  local theme_name
  declare -A seen=()
  declare -a themes=()

  [[ -x "${COLOR_SET_SCRIPT}" ]] || exit 0

  variant="$(theme_precache_resolved_variant)"
  [[ "${variant}" =~ ^(dark|light)$ ]] || variant="dark"

  for theme_name in "$@"; do
    [[ -n "${theme_name}" ]] || continue
    [[ -n "${seen[${theme_name}]:-}" ]] && continue
    seen["${theme_name}"]=1
    themes+=("${theme_name}")
  done

  [[ ${#themes[@]} -gt 0 ]] || exit 0

  for theme_name in "${themes[@]}"; do
    theme_precache_one "${theme_name}" "${variant}"
  done
}

main "$@"
