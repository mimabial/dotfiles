#!/usr/bin/env bash
# shellcheck disable=SC2154,SC1091

source "$(command -v hyprshell)" || exit 1
export_hypr_config

SCRIPT_DIR="${SCRIPT_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")}"
CACHE_ONLY="${HYPR_WAL_CACHE_ONLY:-0}"
PRECACHE_ENABLED=0
PRECACHE_MODE=""
PRECACHE_WALLPAPER=""

apply_color_set_runtime_overrides() {
  local theme_override="${HYPR_THEME_OVERRIDE:-}"
  local color_mode_override="${HYPR_COLOR_MODE_OVERRIDE:-}"

  if [[ -n "${theme_override}" ]]; then
    if [[ ! -d "${HYPR_CONFIG_HOME}/themes/${theme_override}" ]]; then
      print_log -sec "theme" -err "override" "theme not found: ${theme_override}"
      return 1
    fi
    HYPR_THEME="${theme_override}"
    HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  fi

  if [[ -n "${color_mode_override}" ]]; then
    case "${color_mode_override}" in
      0|1|2|3) selected_color_mode="${color_mode_override}" ;;
      *)
        print_log -sec "theme" -err "override" "invalid color mode override: ${color_mode_override}"
        return 1
        ;;
    esac
  fi

  export HYPR_THEME HYPR_THEME_DIR selected_color_mode
}

source_color_module() {
  local module_name="$1"
  local module_path="${SCRIPT_DIR}/${module_name}"

  if [[ ! -r "${module_path}" ]]; then
    print_log -sec "theme" -err "source" "missing required module: ${module_path}"
    return 1
  fi

  # shellcheck source=/dev/null
  source "${module_path}"
}

source_color_modules() {
  local module_name=""
  for module_name in \
    color.lock.sh \
    color.state.sh \
    color.plan.sh \
    color.cache.sh \
    color.apply.sh \
    color.targets.sh \
    color.files.sh \
    color.pipeline.sh \
    color.finalize.sh; do
    source_color_module "${module_name}" || return 1
  done
}

init_color_pipeline() {
  color_lock_init
  color_lock_acquire_run_lock
  color_lock_acquire_theme_update
  trap color_lock_cleanup EXIT
  color_lock_enable_hypr_autoreload_guard

  color_plan_resolve_theme_context
  color_plan_prepare_wal_cache_root
  color_plan_init_cache_controls
}

debug_wal_output() {
  [[ "${LOG_LEVEL}" == "debug" ]] || return 0
  while read -r line; do
    print_log -sec "pywal16" -stat "debug" "${line}"
  done <<<"${wal_output}"
}

run_color_generation() {
  select_palette_source "${1:-}" || return 1
  configure_wal_command
  color_plan_prepare_cache_strategy

  if [[ -z "${wal_exit}" ]]; then
    run_wal_generation
  fi

  color_plan_refresh_cache_key_for_backend_change
  debug_wal_output

  if [[ "${wal_exit}" -ne 0 ]]; then
    print_log -sec "pywal16" -err "failed"
    echo "${wal_output}" >&2
    return 1
  fi
}

finalize_generated_colors() {
  color_finalize_generated_outputs

  if [[ "${CACHE_ONLY}" -eq 1 ]]; then
    print_log -sec "pywal16" -stat "cache" "prepared (cache-only)"
    exit 0
  fi

  color_finalize_load_generated_colors
  color_finalize_primary_theming
  color_finalize_export_icon_theme
  color_finalize_secondary_theming
  color_finalize_terminal_output
  color_finalize_commit_state_and_notify
}

apply_color_set_runtime_overrides || exit 1
source_color_modules || exit 1
init_color_pipeline
run_color_generation "${1:-}" || exit 1
finalize_generated_colors
