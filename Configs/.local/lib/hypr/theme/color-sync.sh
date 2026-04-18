#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# color-sync.sh - Entry point for the live color generation/apply pipeline.

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

SCRIPT_DIR="${SCRIPT_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")}"
CACHE_ONLY="${HYPR_WAL_CACHE_ONLY:-0}"
PRECACHE_ENABLED=0
PRECACHE_MODE=""
PRECACHE_WALLPAPER=""
color_sync_wallpaper_arg=""

color_sync_usage() {
  cat <<'EOF'
Usage: hyprshell theme/color-sync.sh [--refresh|--force-regenerate] [--no-cache] [wallpaper]

Regenerate colors and apply themed outputs.

Options:
  --refresh            Force regeneration and disable cache for this run
  --force-regenerate   Bypass the fast-path/current-cache shortcut
  --no-cache           Disable cache use for this run
  -h, --help           Show this help
EOF
}

color_sync_parse_args() {
  while (($#)); do
    case "$1" in
      -h|--help)
        color_sync_usage
        exit 0
        ;;
      --refresh)
        FORCE_COLOR_REGEN=1
        HYPR_WAL_CACHE_ENABLE=0
        ;;
      --force-regenerate)
        FORCE_COLOR_REGEN=1
        ;;
      --no-cache)
        HYPR_WAL_CACHE_ENABLE=0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'ERROR: unknown option: %s\n' "$1" >&2
        color_sync_usage >&2
        exit 1
        ;;
      *)
        if [[ -n "${color_sync_wallpaper_arg}" ]]; then
          printf 'ERROR: multiple wallpaper arguments provided\n' >&2
          color_sync_usage >&2
          exit 1
        fi
        color_sync_wallpaper_arg="$1"
        ;;
    esac
    shift
  done

  if (($#)); then
    if [[ -n "${color_sync_wallpaper_arg}" ]] || (($# > 1)); then
      printf 'ERROR: multiple wallpaper arguments provided\n' >&2
      color_sync_usage >&2
      exit 1
    fi
    color_sync_wallpaper_arg="$1"
  fi
}

apply_color_sync_runtime_overrides() {
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
  trap 'color_lock_cleanup "$?"' EXIT
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

color_sync_parse_args "$@"
apply_color_sync_runtime_overrides || exit 1
source_color_modules || exit 1
init_color_pipeline
run_color_generation "${color_sync_wallpaper_arg}" || exit 1
finalize_generated_colors
