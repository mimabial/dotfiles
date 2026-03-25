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

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
elif ! declare -F print_log >/dev/null; then
  LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
  if [[ -r "${LIB_DIR}/hypr/globalcontrol.sh" ]]; then
    # shellcheck disable=SC1090
    source "${LIB_DIR}/hypr/globalcontrol.sh"
  fi
fi
if declare -F export_hypr_config >/dev/null; then
  export_hypr_config
fi

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
# shellcheck source=color.cache.sh
[[ -r "${SCRIPT_DIR}/color.cache.sh" ]] && source "${SCRIPT_DIR}/color.cache.sh"
# shellcheck source=color.apply.sh
[[ -r "${SCRIPT_DIR}/color.apply.sh" ]] && source "${SCRIPT_DIR}/color.apply.sh"
# shellcheck source=color.targets.sh
[[ -r "${SCRIPT_DIR}/color.targets.sh" ]] && source "${SCRIPT_DIR}/color.targets.sh"
# shellcheck source=color.files.sh
[[ -r "${SCRIPT_DIR}/color.files.sh" ]] && source "${SCRIPT_DIR}/color.files.sh"
# shellcheck source=color.pipeline.sh
[[ -r "${SCRIPT_DIR}/color.pipeline.sh" ]] && source "${SCRIPT_DIR}/color.pipeline.sh"

# Safe wrapper for hyprctl that logs errors instead of silently failing
# Usage: safe_hyprctl "description" args...
safe_hyprctl() {
  local desc="$1"
  shift
  local output exit_code

  if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE}" ]]; then
    return 0  # Not running under Hyprland, skip silently
  fi

  output=$(hyprctl "$@" 2>&1)
  exit_code=$?

  if [[ ${exit_code} -ne 0 ]]; then
    print_log -sec "hyprctl" -warn "${desc}" "failed (exit ${exit_code}): ${output}"
    return 1
  fi
  return 0
}

# Cache-only mode skips live application and only prepares cached outputs.
CACHE_ONLY="${HYPR_WAL_CACHE_ONLY:-0}"

# ============================================================================
# SECTION 2: LOCK MANAGEMENT
# ============================================================================
LOCK_FILE="$(hypr_lock_path color_gen)"
CACHE_ONLY_LOCK_FILE="$(hypr_lock_path color_cache_only)"
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/color.gen.state"
THEME_UPDATE_LOCK="$(hypr_lock_path theme_update)"
THEME_UPDATE_META="$(hypr_lock_path theme_update_meta)"
THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"
CACHE_ONLY="${CACHE_ONLY:-${HYPR_WAL_CACHE_ONLY:-0}}"
ASYNC_APPS=1
ASYNC_POST_UPDATES=1
MODE_OVERRIDE="${HYPR_WAL_MODE_OVERRIDE:-}"
CACHE_ONLY_ROOT=""
HYPR_AUTO_RELOAD_PREV=""
THEME_UPDATE_LOCK_OWNED=0
THEME_UPDATE_LOCK_FD=""
mkdir -p "$(dirname "$LOCK_FILE")" "$(dirname "$STATE_FILE")"

if [[ "${CACHE_ONLY}" -eq 1 ]]; then
  exec 200>"${CACHE_ONLY_LOCK_FILE}"
  if ! flock -n 200; then
    print_log -sec "pywal16" -stat "skip" "cache-only: another prewarm process running"
    exit 0
  fi
else
  exec 200>"${LOCK_FILE}"
  if ! flock -n 200; then
    print_log -sec "pywal16" -stat "wait" "Another process running"
    flock 200
  fi
fi

# Create theme update lock to prevent waybar from reacting to intermediate changes
if [[ "${CACHE_ONLY}" -ne 1 ]]; then
  if [[ "${HYPR_THEME_UPDATE_EXTERNAL_LOCK:-0}" -ne 1 ]]; then
    exec {THEME_UPDATE_LOCK_FD}>"${THEME_UPDATE_LOCK}"
    flock "${THEME_UPDATE_LOCK_FD}"
    lock_tmp="${THEME_UPDATE_META}.tmp.$$"
    {
      printf 'pid=%s\n' "$$"
      printf 'started=%s\n' "$(date +%s)"
      printf 'cmd=%s\n' "${BASH_SOURCE[0]##*/}"
    } >"${lock_tmp}" && mv -f "${lock_tmp}" "${THEME_UPDATE_META}"
    THEME_UPDATE_LOCK_OWNED=1
  fi
fi

# Pre-cache info (set later, executed in cleanup after lock release)
# Store pre-cache parameters as array elements instead of command string (safer than eval)
PRECACHE_ENABLED=0
PRECACHE_MODE=""
PRECACHE_WALLPAPER=""

# Setup EXIT trap handler to run all cleanup tasks
cleanup() {
  local cleanup_exit_code=$?

  if [[ -n "${CACHE_ONLY_ROOT}" ]]; then
    rm -rf "${CACHE_ONLY_ROOT}" 2>/dev/null || true
  fi
  if [[ "${CACHE_ONLY}" -ne 1 ]]; then
    if [[ "${THEME_UPDATE_LOCK_OWNED}" -eq 1 ]]; then
      rm -f "${THEME_UPDATE_META}"
      flock -u "${THEME_UPDATE_LOCK_FD}" 2>/dev/null || true
      exec {THEME_UPDATE_LOCK_FD}>&-
      THEME_UPDATE_LOCK_FD=""
      THEME_UPDATE_LOCK_OWNED=0
    fi
    # Reload Hyprland config - log failure but don't block cleanup
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]]; then
      if [[ ! -e "${THEME_SWITCH_LOCK}" ]]; then
        if ! hyprctl reload config-only >/dev/null 2>&1; then
          print_log -sec "cleanup" -warn "hyprctl" "config reload failed"
        fi
      fi
      if [[ -n "${HYPR_AUTO_RELOAD_PREV}" ]]; then
        hyprctl keyword misc:disable_autoreload "${HYPR_AUTO_RELOAD_PREV}" -q || true
      fi
    fi
  fi
  # Spawn pre-cache after releasing the lock (safe: no eval, direct execution with validated params)
  if [[ "${PRECACHE_ENABLED}" -eq 1 ]] && [[ -n "${PRECACHE_MODE}" ]] && [[ -n "${PRECACHE_WALLPAPER}" ]]; then
    # Validate mode is one of expected values
    if [[ "${PRECACHE_MODE}" =~ ^(dark|light)$ ]] && [[ -f "${PRECACHE_WALLPAPER}" ]]; then
      flock -u 200  # Release lock first
      (
        export HYPR_WAL_CACHE_ONLY=1
        export HYPR_WAL_MODE_OVERRIDE="${PRECACHE_MODE}"
        bash "${LIB_DIR}/hypr/theme/color.set.sh" "${PRECACHE_WALLPAPER}" &>/dev/null
      ) &
      disown
    fi
  fi
}
trap cleanup EXIT

# Disable Hyprland autoreload during theme application
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" && "${CACHE_ONLY}" -ne 1 ]]; then
  HYPR_AUTO_RELOAD_PREV="$(hyprctl getoption misc:disable_autoreload 2>/dev/null | awk -F': ' '/int/ {print $2; exit}')"
  [[ -n "${HYPR_AUTO_RELOAD_PREV}" ]] && hyprctl keyword misc:disable_autoreload 1 -q
fi

# Check selected_color_mode (0=theme, 1=auto, 2=dark, 3=light)
selected_color_mode="${selected_color_mode:-1}"

# Get resolved light/dark variant from state (auto mode only)
resolved_color_variant="${resolved_color_variant:-dark}"
if [[ -z "${MODE_OVERRIDE}" ]] && [[ "${selected_color_mode}" == "1" ]] && [ -f "$HYPR_STATE_HOME/color_variant" ]; then
  resolved_color_variant=$(cat "$HYPR_STATE_HOME/color_variant")
fi

# Always determine current theme (needed for Kvantum in both modes)
if [ -z "${HYPR_THEME}" ]; then
  # Try to read from wal.conf
  WAL_CONF="${HYPR_CONFIG_HOME}/themes/wal.conf"
  if [ -f "${WAL_CONF}" ]; then
    HYPR_THEME=$(grep '^\$HYPR_THEME=' "${WAL_CONF}" | cut -d'=' -f2)
  fi

  # Fallback to first theme if still not set
  if [ -z "${HYPR_THEME}" ]; then
    if [ -d "${HYPR_CONFIG_HOME}/themes" ]; then
      HYPR_THEME=$(find "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d | sort | head -1 | xargs basename)
    fi
  fi
fi

# Set HYPR_THEME_DIR if we have a theme
if [ -n "${HYPR_THEME}" ] && [ -z "${HYPR_THEME_DIR}" ]; then
  export HYPR_THEME="${HYPR_THEME}"
  export HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  print_log -sec "theme" -stat "detected" "${HYPR_THEME}"
fi

THEME_KITTY_FILE="${HYPR_THEME_DIR}/kitty.theme"
THEME_BG=""
THEME_FG=""
THEME_CURSOR=""
THEME_COLORS=()

SKIP_WAYBAR_UPDATE="${SKIP_WAYBAR_UPDATE:-0}"

# Override mode based on selected_color_mode
case "${selected_color_mode}" in
  2) resolved_color_variant="dark" ;;
  3) resolved_color_variant="light" ;;
esac
if [[ -n "${MODE_OVERRIDE}" ]]; then
  case "${MODE_OVERRIDE}" in
    dark | light) resolved_color_variant="${MODE_OVERRIDE}" ;;
    *) print_log -sec "pywal16" -warn "mode" "invalid override: ${MODE_OVERRIDE}" ;;
  esac
fi

WAL_XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
if [[ "${CACHE_ONLY}" -eq 1 ]]; then
  CACHE_ONLY_ROOT_BASE="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}"
  CACHE_ONLY_ROOT="$(mktemp -d -p "${CACHE_ONLY_ROOT_BASE}" "wal-cache-only.XXXXXXXX")" || {
    print_log -sec "pywal16" -err "cache" "temp dir failed"
    exit 1
  }
  WAL_XDG_CACHE_HOME="${CACHE_ONLY_ROOT}"
fi
WAL_CACHE="${WAL_XDG_CACHE_HOME}/wal"
mkdir -p "${WAL_CACHE}"

CACHE_CLEANUP_ENABLED="${HYPR_WAL_CACHE_CLEANUP:-1}"
CACHE_ASYNC_STORE=1
CACHE_CLEANUP_LOCK="$(hypr_lock_path wal_cache_clean)"
CACHE_STORE_LOCK="$(hypr_lock_path wal_cache_store)"
# Include user template changes in wal cache key.
template_hash_suffix=""

select_palette_source "${1}" || exit 1
configure_wal_command

# Cache pywal output per wallpaper hash + mode (avoids rerunning wal on repeats)
HYPR_WAL_CACHE_ENABLE="${HYPR_WAL_CACHE_ENABLE:-1}"
HYPR_WAL_CACHE_DIR="${HYPR_WAL_CACHE_DIR:-${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wal/cache}"
WAL_CACHE_PRUNE_ENABLED="${HYPR_WAL_CACHE_PRUNE:-1}"
WAL_CACHE_PRUNE_TTL="${HYPR_WAL_CACHE_PRUNE_TTL:-21600}"
WAL_CACHE_PRUNE_LOCK="$(hypr_lock_path wal_cache_prune)"
WAL_CACHE_PRUNE_STAMP="${HYPR_WAL_CACHE_DIR}/.prune.ts"
case "${WAL_CACHE_PRUNE_ENABLED,,}" in
  1 | true | yes | on) WAL_CACHE_PRUNE_ENABLED=1 ;;
  0 | false | no | off) WAL_CACHE_PRUNE_ENABLED=0 ;;
  *) WAL_CACHE_PRUNE_ENABLED=1 ;;
esac
[[ "${WAL_CACHE_PRUNE_TTL}" =~ ^[0-9]+$ ]] || WAL_CACHE_PRUNE_TTL=21600
wal_cache_key=""
wal_cache_path=""
wal_cache_populate=0

wal_used_cache=0
wal_output=""
wal_exit=""

if [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]]; then
  mkdir -p "${HYPR_WAL_CACHE_DIR}" 2>/dev/null || true
  wall_hash="$(${HYPR_HASH_COMMAND:-sha1sum} "${WALLPAPER_IMAGE}" | awk '{print $1}')"
  compute_template_hash
  legibility_suffix="$(compute_legibility_suffix)"
  wal_cache_key="${wall_hash}_${resolved_color_variant}_${PYWAL_BACKEND}${legibility_suffix}${template_hash_suffix}"
  wal_cache_path="${HYPR_WAL_CACHE_DIR}/${wal_cache_key}"
  wal_cache_backend="${PYWAL_BACKEND}"
  queue_cache_cleanup "${HYPR_WAL_CACHE_DIR}" "${template_hash_suffix}"
  queue_wal_cache_prune

  prev_key=""
  previous_selected_color_mode=""
  if [[ -r "${STATE_FILE}" ]]; then
    # Single awk call to get the cache key and selected color mode.
    prev_state="$(awk -F= '
      NR==1 {key=$0}
      /^selected_color_mode=/ {c=$2}
      END {print key"|"c}
    ' "${STATE_FILE}" 2>/dev/null || true)"
    prev_key="${prev_state%%|*}"
    previous_selected_color_mode="${prev_state#*|}"
  fi

  allow_fast_path=0
  if [[ "${FORCE_COLOR_REGEN:-0}" -ne 1 ]]; then
    # Fast-path is allowed only in wallpaper modes. Theme mode always reapplies
    # the generated .theme targets.
    if [[ "${selected_color_mode}" -ne 0 ]]; then
      [[ "${previous_selected_color_mode}" =~ ^[0-9]+$ ]] && [[ "${previous_selected_color_mode}" -ne 0 ]] && allow_fast_path=1
    fi
  fi

  if [[ "${prev_key}" == "${wal_cache_key}" ]]; then
    # When the active cache key is unchanged, wallpaper mode can exit early if
    # the previous run also used wallpaper colors.
    if [[ "${allow_fast_path}" -eq 1 ]]; then
      print_log -sec "pywal16" -stat "cache" "current (fast-path)"
      if [[ "${THEME_UPDATE_LOCK_OWNED}" -eq 1 ]]; then
        rm -f "${THEME_UPDATE_LOCK}"
      fi
      exit 0
    fi
    wal_used_cache=1
    wal_exit=0
    print_log -sec "pywal16" -stat "cache" "current"
  elif wal_cache_valid "${wal_cache_path}"; then
    print_log -sec "pywal16" -stat "cache" "hit"
    if wal_cache_swap_dir "${wal_cache_path}" "${WAL_CACHE}"; then
      wal_used_cache=1
      wal_exit=0
    else
      print_log -sec "pywal16" -warn "cache" "restore failed, regenerating"
      wal_exit=""
    fi
  fi
fi

if [[ -z "${wal_exit}" ]]; then
  run_wal_generation
fi

if [[ "${HYPR_WAL_CACHE_ENABLE}" -eq 1 ]] && [[ -n "${wall_hash:-}" ]] && [[ "${wal_cache_backend:-}" != "${PYWAL_BACKEND}" ]]; then
  wal_cache_key="${wall_hash}_${resolved_color_variant}_${PYWAL_BACKEND}${legibility_suffix}${template_hash_suffix}"
  wal_cache_path="${HYPR_WAL_CACHE_DIR}/${wal_cache_key}"
fi

[[ "${LOG_LEVEL}" == "debug" ]] && echo "${wal_output}" | while read -r line; do
  print_log -sec "pywal16" -stat "debug" "${line}"
done

[ "${wal_exit}" -ne 0 ] && {
  print_log -sec "pywal16" -err "failed"
  echo "${wal_output}" >&2
  exit 1
}

print_log -sec "pywal16" -stat "complete" "color generation"

canonicalize_shell_colors_file

# Generate hyprlock integer rgba colors
if [ -f "${LIB_DIR}/hypr/wal/wal.hyprlock.sh" ]; then
  bash "${LIB_DIR}/hypr/wal/wal.hyprlock.sh"
  print_log -sec "hyprlock" -stat "generated" "integer rgba colors"
fi

post_process_generated_color_files

if [[ "${wal_cache_populate}" -eq 1 ]] && [[ "${wal_used_cache}" -eq 0 ]] && [[ -n "${wal_cache_path}" ]]; then
  if [[ "${CACHE_ONLY}" -ne 1 ]]; then
    wal_cache_store_async "${WAL_CACHE}" "${wal_cache_path}"
  else
    wal_cache_store_with_lock "${WAL_CACHE}" "${wal_cache_path}" || print_log -sec "pywal16" -warn "cache" "store failed"
  fi
fi

queue_opposite_mode_precache

if [[ "${CACHE_ONLY}" -eq 1 ]]; then
  print_log -sec "pywal16" -stat "cache" "prepared (cache-only)"
  exit 0
fi

# Source pywal16-generated colors
set -a
[ -f "${WAL_CACHE}/colors-shell.sh" ] && source "${WAL_CACHE}/colors-shell.sh"
set +a

link_generated_color_files

if [[ "${selected_color_mode}" -eq 0 ]]; then
  if ! generate_hypr_colors_from_theme; then
    print_log -sec "theme" -warn "colors" "falling back to pywal16 Hyprland colors"
    ln -sf "${WAL_CACHE}/colors-hyprland.conf" "${HOME}/.config/hypr/themes/colors.conf" 2>/dev/null || true
  fi
fi

# Kvantum theme application is delegated to wal.kvantum.sh in parallel.

print_log -sec "pywal16" -stat "complete" "color files ready"

# Application theming - deploy generated templates (run in parallel)
print_log -sec "pywal16" -stat "deploy" "applying themes to applications"

# Get hypr_border early for scripts that need it
theme_conf="${HYPR_CONFIG_HOME}/themes/theme.conf"
if [ -f "${theme_conf}" ]; then
  hypr_border=$(grep "rounding" "${theme_conf}" | grep "=" | head -1 | awk '{print $NF}')
  export hypr_border
fi

# ============================================================================
# APP THEMING - Run independent theming scripts in parallel
# ============================================================================
run_app_theming

if [[ "${ASYNC_APPS}" -eq 1 ]]; then
  print_log -sec "pywal16" -stat "async" "app theming running in background (${#APP_THEMING_PIDS[@]} jobs)"
fi

# Wait for all background app theming jobs to complete
wait_for_theming_jobs_when_async_disabled

# Hyprshade color normalization (convert RGB 0-255 to 0.0-1.0 range for GLSL)
hyprshade_colors_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wal/colors.inc"
if [[ -L "${hyprshade_colors_file}" ]]; then
  hyprshade_colors_file="$(readlink -f "${hyprshade_colors_file}")"
fi
if [ -f "${hyprshade_colors_file}" ]; then
  sed -i 's/vec3(\([0-9]\+\), \([0-9]\+\), \([0-9]\+\))/vec3(\1\/255.0, \2\/255.0, \3\/255.0)/g' "${hyprshade_colors_file}"
fi

# Reload live applications
reload_live_apps

# Only process .theme files in theme mode
if [ "${selected_color_mode}" -eq 0 ]; then
  process_theme_files
else
  apply_wallpaper_mode_theme_fallbacks
fi

# Run non-critical theming operations in parallel for speed
# These don't need to block the main theme application

if command -v hyq &>/dev/null; then
  theme_conf="${HYPR_CONFIG_HOME}/themes/theme.conf"
  if [ "${selected_color_mode}" -eq 0 ] && [ -r "${theme_conf}" ]; then
    hyq_out="$(hyq "${theme_conf}" --export env --allow-missing -Q "\$ICON_THEME[string]" 2>/dev/null)"
    hyq_icon="$(_safe_hyq_get "${hyq_out}" "ICON_THEME")"
    [ -n "${hyq_icon}" ] && ICON_THEME="${hyq_icon}"
  elif [ -z "${ICON_THEME}" ]; then
    hyq_out="$(hyq "${HYPR_CONFIG_HOME}/hyprland.conf" --source --export env --allow-missing -Q "\$ICON_THEME[string]" 2>/dev/null)"
    hyq_icon="$(_safe_hyq_get "${hyq_out}" "ICON_THEME")"
    ICON_THEME="${hyq_icon:-$ICON_THEME}"
  fi
fi
export ICON_THEME

# ============================================================================
# SECONDARY APP THEMING - Non-critical apps that depend on ICON_THEME
# ============================================================================

# Hyprland metadata (fast, run inline - provides variables for other scripts)
[ -f "${LIB_DIR}/hypr/wal/wal.hypr.sh" ] && source "${LIB_DIR}/hypr/wal/wal.hypr.sh"

run_secondary_theming

# Wait for parallel operations to complete (with timeout)
wait_for_theming_jobs_when_async_disabled

# Update Waybar border radius before background tasks so it stays within the active theme update lock
  if [[ "${SKIP_WAYBAR_UPDATE}" -ne 1 ]]; then
    if [[ -x "${LIB_DIR}/hypr/waybar/waybar.py" ]]; then
      WAYBAR_BORDER_RADIUS="${hypr_border:-}" "${LIB_DIR}/hypr/waybar/waybar.py" --update-border-radius &>/dev/null
      print_log -sec "waybar" -stat "updated" "border-radius from theme"
    elif command -v hyprshell &>/dev/null; then
      WAYBAR_BORDER_RADIUS="${hypr_border:-}" hyprshell waybar --update-border-radius &>/dev/null
      print_log -sec "waybar" -stat "updated" "border-radius from theme"
    fi
  fi

# Release the active theme update lock once Waybar files are settled.
if [[ "${CACHE_ONLY}" -ne 1 ]]; then
  if [[ "${THEME_UPDATE_LOCK_OWNED}" -eq 1 ]]; then
    rm -f "${THEME_UPDATE_META}"
    flock -u "${THEME_UPDATE_LOCK_FD}" 2>/dev/null || true
    exec {THEME_UPDATE_LOCK_FD}>&-
    THEME_UPDATE_LOCK_FD=""
    THEME_UPDATE_LOCK_OWNED=0
  fi
fi

# post_updates writes KDE/kdeglobals settings.
# Keep async execution to avoid blocking callers.
# Redirect output to avoid partial line "%" in zsh when background output appears after prompt.
if [[ "${ASYNC_POST_UPDATES}" -eq 1 ]]; then
  post_updates &>/dev/null &
else
  post_updates &>/dev/null
fi

# Print colors if in terminal
[ -t 1 ] && [ -f "${LIB_DIR}/hypr/wal/wal.print.colors.sh" ] && bash "${LIB_DIR}/hypr/wal/wal.print.colors.sh"

previous_color_variant=""
previous_selected_color_mode=""
if [[ -r "${STATE_FILE}" ]]; then
  # Single awk call to extract both values
  prev_state="$(awk -F= '
    /^color_variant=/ {m=$2}
    /^selected_color_mode=/ {c=$2}
    END {print m"|"c}
  ' "${STATE_FILE}")"
  previous_color_variant="${prev_state%%|*}"
  previous_selected_color_mode="${prev_state#*|}"
fi
color_variant_changed=false
selected_color_mode_changed=false
[[ -n "${previous_color_variant}" && "${previous_color_variant}" != "${resolved_color_variant}" ]] && color_variant_changed=true
[[ -n "${previous_selected_color_mode}" && "${previous_selected_color_mode}" != "${selected_color_mode}" ]] && selected_color_mode_changed=true

# State
state_wallpaper="${STATE_WALLPAPER:-${WALLPAPER_IMAGE:-theme}}"
{
  echo "${wal_cache_key:-${state_wallpaper}:${resolved_color_variant}}"
  echo "wallpaper=${state_wallpaper}"
  echo "color_variant=${resolved_color_variant}"
  echo "selected_color_mode=${selected_color_mode}"
  echo "backend=${PYWAL_BACKEND}"
} >"${STATE_FILE}"

# Notify
if [[ "${CACHE_ONLY}" -ne 1 ]] && [[ "${color_variant_changed}" == true || "${selected_color_mode_changed}" == true ]]; then
  command -v dunstify &>/dev/null \
    && dunstify "Theme Updated" "${resolved_color_variant} mode" -i preferences-desktop-theme -t 2000
fi

print_log -sec "pywal16" -stat "complete" "applied"
