#!/usr/bin/env bash
#
# Subsystem inputs (populated by core/wallpaper.catalog.sh:get_themes):
#   thmList
: "${thmList-}"
#
# theme.switch.sh - Theme switching orchestrator
#
# OVERVIEW:
#   Switches themes and updates live desktop configuration.
#
# USAGE:
#   theme.switch.sh -s "Theme Name"   # Switch to specific theme
#   theme.switch.sh -n                # Switch to next theme
#   theme.switch.sh -p                # Switch to previous theme
#
set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

[ -z "${HYPR_THEME}" ] && echo "ERROR: unable to detect theme" && exit 1
get_themes

theme_switch_previous_theme="${HYPR_THEME:-}"
theme_switch_state_updated=0
theme_switch_metadata_file=""
THEME_SWITCH_NOTIFY_ID="${THEME_SWITCH_NOTIFY_ID:-94}"
THEME_SWITCH_NOTIFY_STACK_TAG="${THEME_SWITCH_NOTIFY_STACK_TAG:-theme-switch}"

# Lock file to prevent concurrent theme switching
THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"

exec 201>"${THEME_SWITCH_LOCK}"
! flock -n 201 && {
  print_log -sec "theme.switch" -stat "drop" "Another theme operation is already in progress"
  exit 0
}

sanitize_hypr_theme() {
  local input_file="$1"
  local output_file="$2"
  local buffer_file=""
  local pattern=""
  local line=""
  local line_esc=""
  local log_line=""
  local -a dirty_regex=(
    "^ *exec"
    "^ *decoration[^:]*: *drop_shadow"
    "^ *drop_shadow"
    "^ *decoration[^:]*: *shadow *="
    "^ *decoration[^:]*: *col.shadow* *="
    "^ *shadow_"
    "^ *col.shadow*"
    "^ *col\.(active_border|inactive_border|border_(active|inactive|locked_active|locked_inactive))"
  )

  [[ -n "${HYPR_CONFIG_SANITIZE+set}" ]] && dirty_regex+=("${HYPR_CONFIG_SANITIZE[@]}")
  buffer_file="$(mktemp)" || return 1

  if ! sed '1d' "${input_file}" >"${buffer_file}"; then
    rm -f -- "${buffer_file}"
    return 1
  fi

  for pattern in "${dirty_regex[@]}"; do
    local -a matches=()
    while IFS= read -r line; do
      matches+=("$line")
    done < <(grep -E "${pattern}" "${buffer_file}" 2>/dev/null)

    for line in "${matches[@]}"; do
      [[ -n "${line}" ]] || continue
      line_esc="$(escape_regex "${line}")"
      if ! sed -i -E "\|${line_esc}|d" "${buffer_file}"; then
        rm -f -- "${buffer_file}"
        return 1
      fi
      log_line="${line#"${line%%[![:space:]]*}"}"
      print_log -sec "theme" -warn "sanitize" "${log_line}"
    done
  done

  if ! cat "${buffer_file}" >"${output_file}"; then
    rm -f -- "${buffer_file}"
    return 1
  fi
  rm -f -- "${buffer_file}"
}

select_adjacent_theme() {
  local direction="$1"
  local found=false
  local i=""

  if [[ ! "${direction}" =~ ^[np]$ ]]; then
    print_log -sec "theme" -err "select_adjacent_theme" "invalid direction '${direction}' (expected 'n' or 'p')"
    return 1
  fi

  for i in "${!thmList[@]}"; do
    if [[ "${thmList[i]}" == "${HYPR_THEME}" ]]; then
      found=true
      if [[ "${direction}" == "n" ]]; then
        setIndex=$(((i + 1) % ${#thmList[@]}))
      else
        setIndex=$((i - 1))
        [[ ${setIndex} -lt 0 ]] && setIndex=$((${#thmList[@]} - 1))
      fi
      themeSet="${thmList[setIndex]}"
      break
    fi
  done

  if [[ "${found}" != true ]]; then
    print_log -sec "theme" -warn "select_adjacent_theme" "current theme '${HYPR_THEME}' not found in theme list"
    setIndex=0
    themeSet="${thmList[0]}"
  fi
}

theme_notify_finish() {
  local exit_code="$1"
  local theme_name="${themeSet:-${HYPR_THEME}}"
  [[ -z "${exit_code}" ]] && exit_code=0

  if [[ "${exit_code}" -ne 0 ]]; then
    theme_notify_send "Theme switch interrupted" "${theme_name}" 2500 critical
  fi
}

theme_notify_send() {
  local summary="$1"
  local body="$2"
  local timeout_ms="${3:-2000}"
  local urgency="${4:-normal}"
  local icon_path="preferences-desktop-theme"
  local -a args=(
    -a "Theme switch"
    -u "${urgency}"
    -t "${timeout_ms}"
  )
  [[ -f "${HOME}/.face.icon" ]] && icon_path="${HOME}/.face.icon"
  args+=(-i "${icon_path}")

  if command -v dunstify >/dev/null 2>&1; then
    dunstify \
      "${args[@]}" \
      -r "${THEME_SWITCH_NOTIFY_ID}" \
      --stack-tag "${THEME_SWITCH_NOTIFY_STACK_TAG}" \
      "${summary}" "${body}" >/dev/null 2>&1 || true
    return 0
  fi

  notify_send_safe \
    "${args[@]}" \
    -h "string:x-canonical-private-synchronous:${THEME_SWITCH_NOTIFY_STACK_TAG}" \
    "${summary}" "${body}" >/dev/null 2>&1 || true
}

cleanup_theme_switch() {
  local exit_code="${1:-$?}"
  if [[ "${exit_code}" -ne 0 ]] && [[ "${theme_switch_state_updated}" -eq 1 ]] && [[ -n "${theme_switch_previous_theme}" ]]; then
    state_set "HYPR_THEME" "${theme_switch_previous_theme}" "staterc" || true
  fi
  [[ -n "${theme_switch_metadata_file}" && -e "${theme_switch_metadata_file}" ]] && rm -f -- "${theme_switch_metadata_file}"
  theme_notify_finish "${exit_code}"
  flock -u 201 2>/dev/null || true
  return "${exit_code}"
}
trap 'cleanup_theme_switch "$?"' EXIT

quiet=false
theme_switch_cache_args=()

theme_switch_usage() {
  cat <<EOF
Usage: $(basename "${0}") [options]

Options:
  -n, --next              Set next theme
  -p, --previous          Set previous theme
  -s, --set THEME         Set theme by name
  -q, --quiet             Suppress nonessential output
      --regen             Regenerate colors and refresh cache
      --force-regenerate  Alias for --regen
      --no-cache          Bypass cache reads and writes
EOF
}

parse_theme_switch_args() {
  while (($#)); do
    case "$1" in
      -n | --next)
        select_adjacent_theme n
        ;;
      -p | --previous | --prev)
        select_adjacent_theme p
        ;;
      -s | --set)
        shift
        if [[ -z "${1:-}" ]]; then
          theme_switch_usage >&2
          exit 1
        fi
        themeSet="$1"
        ;;
      -s?*)
        themeSet="${1#-s}"
        ;;
      -q | --quiet)
        quiet=true
        ;;
      --regen | --force-regenerate)
        theme_switch_cache_args+=(--force-regenerate)
        ;;
      --no-cache)
        theme_switch_cache_args+=(--no-cache)
        ;;
      -h | --help)
        theme_switch_usage
        exit 0
        ;;
      *)
        theme_switch_usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

set_active_theme() {
  local theme_exists=0
  local theme_name=""

  for theme_name in "${thmList[@]}"; do
    if [[ "${theme_name}" == "${themeSet}" ]]; then
      theme_exists=1
      break
    fi
  done

  [[ "${theme_exists}" -eq 1 ]] || themeSet="${HYPR_THEME}"
  state_set "HYPR_THEME" "${themeSet}" "staterc"
  theme_switch_state_updated=1
  HYPR_THEME="${themeSet}"
  HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  export HYPR_THEME HYPR_THEME_DIR
  print_log -sec "theme" -stat "apply" "${themeSet}"
}

prepare_active_theme_config() {
  [[ -r "${HYPR_THEME_DIR}/hypr.theme" ]] || return 0
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/hypr" || return 1
  theme_switch_metadata_file="$(mktemp "${XDG_CACHE_HOME:-$HOME/.cache}/hypr/theme.conf.XXXXXX")" || return 1
  sanitize_hypr_theme "${HYPR_THEME_DIR}/hypr.theme" "${theme_switch_metadata_file}"
}

main() {
  local -a theme_apply_cmd=("${LIB_DIR}/hypr/theme/theme.apply.sh")

  parse_theme_switch_args "$@"
  set_active_theme
  prepare_active_theme_config || exit 1
  [[ "${quiet}" == "true" ]] && theme_apply_cmd+=(--quiet)
  theme_apply_cmd+=("${theme_switch_cache_args[@]}")
  HYPR_THEME_METADATA_FILE="${theme_switch_metadata_file}" "${theme_apply_cmd[@]}" || exit 1
}

main "$@"
