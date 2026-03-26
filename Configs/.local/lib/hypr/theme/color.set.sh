#!/usr/bin/env bash
# shellcheck disable=SC2154,SC1091
# ============================================================================
# COLOR.SET.SH - Main color generation and application orchestrator
# ============================================================================
#
# OVERVIEW:
#   Generates colors from wallpaper using pywal16 and applies them to all
#   themed applications (GTK, Qt, terminals, waybar, etc.)
#
# SECTIONS:
#   1. INITIALIZATION     - Load dependencies, acquire locks
#   2. CONFIGURATION      - Read state, determine color mode
#   3. CACHING            - Wallpaper hash caching for fast re-runs
#   4. COLOR GENERATION   - Run pywal16 to extract colors
#   5. POST-PROCESSING    - Convert colors to app-specific formats
#   6. SYMLINK CREATION   - Link color files to expected locations
#   7. APP THEMING        - Apply colors to applications (parallel)
#   8. FINALIZATION       - Update state, send notifications
#
# DEPENDENCIES:
#   - globalcontrol.sh (sourced via hyprshell init)
#   - pywal16 (wal command)
#   - hyprctl (optional, for Hyprland integration)
#   - Various wal/*.sh scripts for app-specific theming
#
# ENVIRONMENT:
#   HYPR_WAL_CACHE_ONLY=1    - Only generate cache, don't apply
#   HYPR_WAL_CACHE_CLEANUP=1 - Async cleanup stale cache entries
#   HYPR_WAL_CACHE_PRUNE=1   - Auto-prune wal cache entries for missing wallpapers/themes
#   HYPR_WAL_CACHE_PRUNE_TTL=21600 - Minimum seconds between prune runs
#   HYPR_WAL_MODE_OVERRIDE   - Force dark/light mode
#   HYPR_THEME_OVERRIDE      - Force a specific theme directory for this run
#   HYPR_COLOR_MODE_OVERRIDE - Force selected_color_mode for this run
#   selected_color_mode           - Color mode (0=theme, 1=auto, 2=dark, 3=light)
#
# ============================================================================

# ============================================================================
# SECTION 1: INITIALIZATION
# ============================================================================

source "$(command -v hyprshell)" || exit 1
export_hypr_config

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
      0 | 1 | 2 | 3) selected_color_mode="${color_mode_override}" ;;
      *)
        print_log -sec "theme" -err "override" "invalid color mode override: ${color_mode_override}"
        return 1
        ;;
    esac
  fi

  export HYPR_THEME HYPR_THEME_DIR selected_color_mode
}

apply_color_set_runtime_overrides || exit 1

# Source modular components
SCRIPT_DIR="${SCRIPT_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")}"

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

source_color_module "color.lock.sh" || exit 1
source_color_module "color.state.sh" || exit 1
source_color_module "color.plan.sh" || exit 1
source_color_module "color.cache.sh" || exit 1
source_color_module "color.apply.sh" || exit 1
source_color_module "color.targets.sh" || exit 1
source_color_module "color.files.sh" || exit 1
source_color_module "color.pipeline.sh" || exit 1
source_color_module "color.finalize.sh" || exit 1

# Cache-only mode skips live application and only prepares cached outputs.
CACHE_ONLY="${HYPR_WAL_CACHE_ONLY:-0}"

# Pre-cache info (set later, executed in cleanup after lock release)
# Store pre-cache parameters as array elements instead of command string (safer than eval)
PRECACHE_ENABLED=0
PRECACHE_MODE=""
PRECACHE_WALLPAPER=""

color_lock_init
color_lock_acquire_run_lock
color_lock_acquire_theme_update
trap color_lock_cleanup EXIT
color_lock_enable_hypr_autoreload_guard

color_plan_resolve_theme_context
color_plan_prepare_wal_cache_root
color_plan_init_cache_controls

select_palette_source "${1}" || exit 1
configure_wal_command
color_plan_prepare_cache_strategy

if [[ -z "${wal_exit}" ]]; then
  run_wal_generation
fi

color_plan_refresh_cache_key_for_backend_change

[[ "${LOG_LEVEL}" == "debug" ]] && echo "${wal_output}" | while read -r line; do
  print_log -sec "pywal16" -stat "debug" "${line}"
done

[ "${wal_exit}" -ne 0 ] && {
  print_log -sec "pywal16" -err "failed"
  echo "${wal_output}" >&2
  exit 1
}

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
