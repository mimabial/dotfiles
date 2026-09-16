#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system wallpaper_catalog || exit 1

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/theme/pairs.sh" || exit 1

THEME_SWITCH_LOCK="$(hypr_lock_path theme_switch)"
exec {theme_switch_lock_fd}>"${THEME_SWITCH_LOCK}"
if ! flock -n "${theme_switch_lock_fd}"; then
  for theme_switch_arg in "$@"; do
    [[ "${theme_switch_arg}" == "--from-auto" ]] || continue
    print_log -sec "theme.switch" -stat "drop" "A newer theme operation is already in progress"
    exit 0
  done
  unset theme_switch_arg
  print_log -sec "theme.switch" -stat "wait" "Another theme operation is in progress"
  flock "${theme_switch_lock_fd}"
fi

hypr_runtime_load_state || exit 1
[[ -n "${HYPR_THEME}" ]] || { echo "ERROR: unable to detect theme"; exit 1; }
get_themes
theme_switch_previous_theme="${HYPR_THEME:-}"
theme_switch_previous_color_mode="${selected_color_mode:-}"
theme_switch_state_updated=0
theme_switch_auto_mode_changed=0
theme_switch_metadata_file=""
theme_switch_nvim_mapping=""
theme_switch_nvim_background=""
theme_switch_nvim_transparency=""
THEME_SWITCH_NOTIFY_ID="${THEME_SWITCH_NOTIFY_ID:-94}"
THEME_SWITCH_NOTIFY_STACK_TAG="${THEME_SWITCH_NOTIFY_STACK_TAG:-theme-switch}"

sanitize_hypr_theme() {
  local input_file="$1"
  local output_file="$2"
  local buffer_file=""
  local pattern=""
  local line=""
  local line_esc=""
  local log_line=""
  local -a warn_regex=(
    "^ *exec"
    "^ *decoration[^:]*: *drop_shadow"
    "^ *drop_shadow"
    "^ *decoration[^:]*: *shadow *="
    "^ *decoration[^:]*: *col.shadow* *="
    "^ *shadow_"
    "^ *col.shadow*"
  )
  local -a quiet_regex=(
    "^ *col\.(active_border|inactive_border|border_(active|inactive|locked_active|locked_inactive))"
  )
  local -a dirty_regex=("${warn_regex[@]}" "${quiet_regex[@]}")

  if [[ -n "${HYPR_CONFIG_SANITIZE+set}" ]]; then
    warn_regex+=("${HYPR_CONFIG_SANITIZE[@]}")
    dirty_regex+=("${HYPR_CONFIG_SANITIZE[@]}")
  fi
  buffer_file="$(mktemp)" || return 1

  if ! sed '1d' "${input_file}" >"${buffer_file}"; then
    rm -f -- "${buffer_file}"
    return 1
  fi

  local combined_regex
  combined_regex="$(IFS='|'; printf '%s' "${warn_regex[*]}")"

  while IFS= read -r line; do
    log_line="${line#"${line%%[![:space:]]*}"}"
    print_log -sec "theme" -warn "sanitize" "${log_line}"
  done < <(grep -E "${combined_regex}" "${buffer_file}" 2>/dev/null || true)

  local -a sed_args=()
  for pattern in "${dirty_regex[@]}"; do
    sed_args+=(-e "/${pattern}/d")
  done
  if ! sed -i -E "${sed_args[@]}" "${buffer_file}"; then
    rm -f -- "${buffer_file}"
    return 1
  fi

  if ! cat "${buffer_file}" >"${output_file}"; then
    rm -f -- "${buffer_file}"
    return 1
  fi
  rm -f -- "${buffer_file}"
}

select_adjacent_theme() {
  local direction="$1"

  if [[ ! "${direction}" =~ ^[np]$ ]]; then
    print_log -sec "theme" -err "select_adjacent_theme" "invalid direction '${direction}' (expected 'n' or 'p')"
    return 1
  fi

  local index=""
  if index="$(catalog_index_of thmList "${HYPR_THEME}")"; then
    setIndex="$(catalog_adjacent_index "${index}" "${direction}" "${#thmList[@]}")" || return 1
  else
    print_log -sec "theme" -warn "select_adjacent_theme" "current theme '${HYPR_THEME}' not found in theme list"
    setIndex=0
  fi
  themeSet="${thmList[setIndex]}"
}

theme_notify_finish() {
  local exit_code="$1"
  local theme_name="${themeSet:-${HYPR_THEME}}"
  [[ -z "${exit_code}" ]] && exit_code=0

  if [[ "${exit_code}" -ne 0 && "${theme_switch_state_updated}" -eq 1 ]]; then
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
  if [[ "${exit_code}" -ne 0 ]] && [[ "${theme_switch_auto_mode_changed}" -eq 1 ]]; then
    state_set "selected_color_mode" "${theme_switch_previous_color_mode}" "staterc" || true
    hypr_svc_user start auto-theme || true
    hypr_svc_user_signal auto-theme USR2 || true
  fi
  [[ -n "${theme_switch_metadata_file}" && -e "${theme_switch_metadata_file}" ]] && rm -f -- "${theme_switch_metadata_file}"
  theme_notify_finish "${exit_code}"
  flock -u "${theme_switch_lock_fd}" 2>/dev/null || true
  return "${exit_code}"
}
trap 'cleanup_theme_switch "$?"' EXIT

quiet=false
themeSet=""
theme_switch_selection_requested=0
theme_switch_from_auto=0
theme_switch_cache_args=()

theme_switch_usage() {
  cat <<EOF
Usage: $(basename "${0}") [options]
Switch the active theme pack: step to the next or previous, or set one by name.

Options:
  -n, --next              Set next theme
  -p, --previous          Set previous theme
  -s, --set THEME         Set theme by name
  -q, --quiet             Suppress nonessential output
      --regen             Regenerate colors and refresh cache
      --force-regenerate  Alias for --regen
      --no-cache          Bypass cache reads and writes
      --from-auto         Preserve auto mode for scheduler-driven switches
      --nvim SCHEME[:VARIANT]
                          Persist the active pack's Neovim mapping
      --nvim-background MODE
      --nvim-transparency BOOL
EOF
}

parse_theme_switch_args() {
  while (($#)); do
    case "$1" in
      -n | --next)
        theme_switch_selection_requested=1
        select_adjacent_theme n
        ;;
      -p | --previous | --prev)
        theme_switch_selection_requested=1
        select_adjacent_theme p
        ;;
      -s | --set)
        shift
        if [[ -z "${1:-}" ]]; then
          theme_switch_usage >&2
          exit 1
        fi
        theme_switch_selection_requested=1
        themeSet="$1"
        ;;
      -s?*)
        theme_switch_selection_requested=1
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
      --from-auto)
        theme_switch_from_auto=1
        ;;
      --nvim)
        shift
        [[ -n "${1:-}" ]] || { theme_switch_usage >&2; exit 1; }
        theme_switch_nvim_mapping="$1"
        ;;
      --nvim-background)
        shift
        theme_switch_nvim_background="${1:-}"
        ;;
      --nvim-transparency)
        shift
        theme_switch_nvim_transparency="${1:-}"
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

update_nvim_mapping() {
  [[ -n "${theme_switch_nvim_mapping}" ]] || return 0
  local file="${HYPR_THEME_DIR}/hypr.theme"
  local scheme="${theme_switch_nvim_mapping%%:*}"
  local variant="" tmp=""
  [[ "${theme_switch_nvim_mapping}" == *:* ]] && variant="${theme_switch_nvim_mapping#*:}"
  [[ "${scheme}" =~ ^[[:alnum:]_.-]+$ && ( -z "${variant}" || "${variant}" =~ ^[[:alnum:]_.-]+$ ) ]] || return 1
  [[ -z "${theme_switch_nvim_background}" || "${theme_switch_nvim_background}" =~ ^(dark|light)$ ]] || return 1
  [[ -z "${theme_switch_nvim_transparency}" || "${theme_switch_nvim_transparency}" =~ ^(true|false)$ ]] || return 1
  [[ -s "${file}" ]] || return 1

  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
  if awk -v scheme="${scheme}" -v variant="${variant}" \
    -v background="${theme_switch_nvim_background}" -v transparency="${theme_switch_nvim_transparency}" '
    NR == 1 {
      print; print "$NVIM_SCHEME = " scheme
      if (variant != "") print "$NVIM_VARIANT = " variant
      if (background != "") print "$NVIM_BACKGROUND = " background
      if (transparency != "") print "$NVIM_TRANSPARENCY = " transparency
      next
    }
    /^[[:space:]]*\$NVIM_(SCHEME|VARIANT)[[:space:]]*=/ { next }
    background != "" && /^[[:space:]]*\$NVIM_BACKGROUND[[:space:]]*=/ { next }
    transparency != "" && /^[[:space:]]*\$NVIM_TRANSPARENCY[[:space:]]*=/ { next }
    { print }
  ' "${file}" >"${tmp}" && chmod --reference="${file}" "${tmp}" && mv -f -- "${tmp}" "${file}"; then
    return 0
  fi
  rm -f -- "${tmp}"
  return 1
}

resolve_theme_selection() {
  local theme_exists=0
  local theme_name=""

  for theme_name in "${thmList[@]}"; do
    if [[ "${theme_name}" == "${themeSet}" ]]; then
      theme_exists=1
      break
    fi
  done

  [[ "${theme_exists}" -eq 1 ]] || themeSet="${HYPR_THEME}"
}

set_active_theme() {
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
  theme_switch_metadata_file="$(mktemp "${XDG_CACHE_HOME:-$HOME/.cache}/hypr/theme.meta.XXXXXX")" || return 1
  sanitize_hypr_theme "${HYPR_THEME_DIR}/hypr.theme" "${theme_switch_metadata_file}"
}

theme_switch_reconcile_color_mode() {
  local mode polarity desired
  mode="${selected_color_mode}"
  [[ "${mode}" =~ ^[1-3]$ ]] || return 0
  polarity="$(theme_polarity "${themeSet}")"
  [[ "${polarity}" == "light" ]] && desired=3 || desired=2

  if [[ "${mode}" == "1" ]]; then
    [[ "${theme_switch_selection_requested}" -eq 1 && "${theme_switch_from_auto}" -eq 0 ]] || return 0
    theme_switch_auto_mode_changed=1
    hypr_svc_user stop auto-theme || true
  fi

  [[ "${desired}" == "${mode}" ]] && return 0
  state_set "selected_color_mode" "${desired}" "staterc"
  selected_color_mode="${desired}"
  export selected_color_mode
}

main() {
  local -a theme_apply_cmd=("${LIB_DIR}/hypr/theme/theme.apply.sh")

  parse_theme_switch_args "$@"
  if [[ "${theme_switch_from_auto}" -eq 1 && "${selected_color_mode:-}" != 1 ]]; then
    print_log -sec "theme.switch" -stat "skip" "Auto mode is no longer active"
    return 0
  fi
  resolve_theme_selection
  theme_switch_reconcile_color_mode
  set_active_theme
  update_nvim_mapping || exit 1
  prepare_active_theme_config || exit 1
  [[ "${quiet}" == "true" ]] && theme_apply_cmd+=(--quiet)
  theme_apply_cmd+=("${theme_switch_cache_args[@]}")
  HYPR_THEME_METADATA_FILE="${theme_switch_metadata_file}" "${theme_apply_cmd[@]}" || exit 1
}

main "$@"
