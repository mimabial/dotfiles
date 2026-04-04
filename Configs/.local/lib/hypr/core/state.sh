#!/usr/bin/env bash

export_hypr_config() {
  # Reload runtime state into the current shell.
  # Use this after state changes, in a fresh shell, or when array variables
  # need to be populated locally (bash does not export arrays).

  local user_conf_state=""
  local user_conf=""
  user_conf_state="$(state_rc_file)"
  user_conf="$(state_env_overrides_file)"

  [ -f "${user_conf_state}" ] && source "${user_conf_state}"
  [ -f "${user_conf}" ] && source "${user_conf}"
  refresh_hypr_runtime_state
}

refresh_hypr_runtime_state() {
  # Keep derived theme/runtime paths in sync after reloading state.
  case "${selected_color_mode}" in
    0 | 1 | 2 | 3) ;;
    *) selected_color_mode=0 ;;
  esac

  if [ -z "${HYPR_THEME}" ] || [ ! -d "${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}" ]; then
    get_themes
    HYPR_THEME="${thmList[0]}"
  fi

  HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  export HYPR_THEME HYPR_THEME_DIR selected_color_mode
}

# ============================================================================
# UNIFIED STATE MANAGEMENT
# ============================================================================
# All state is stored in key=value format in these files:
#   - staterc:        User/runtime state (HYPR_THEME, selected_color_mode, etc.)
#   - env-overrides:  Exported environment overrides
#   - color_variant:  Current resolved dark/light variant
#
# Use these functions for consistent state access across all scripts:
#   state_get  - Read a state variable
#   state_set  - Write a state variable (atomic)
#   state_get_color_variant - Read the resolved dark/light variant
#   state_set_color_variant - Write the resolved dark/light variant
# ============================================================================

# State path resolution
state_dir() {
  printf '%s\n' "${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
}

state_rc_file() {
  printf '%s\n' "${STATE_RC:-$(state_dir)/staterc}"
}

state_env_overrides_file() {
  printf '%s\n' "${STATE_ENV_OVERRIDES:-$(state_dir)/env-overrides}"
}

state_color_variant_file() {
  printf '%s\n' "${STATE_COLOR_VARIANT:-$(state_dir)/color_variant}"
}

state_read_value_from_file() {
  local state_file="$1"
  local var_name="$2"

  [[ -f "${state_file}" ]] || return 1

  bash -c '
    state_file="$1"
    var_name="$2"
    source "${state_file}" >/dev/null 2>&1 || exit 1
    declare -p "${var_name}" >/dev/null 2>&1 || exit 1
    printf "%s" "${!var_name}"
  ' _ "${state_file}" "${var_name}"
}

# Get a state variable value
# Usage: state_get VARIABLE_NAME [default_value]
# Checks: staterc, env-overrides, then returns default
state_get() {
  local var_name="$1"
  local default_value="${2:-}"
  local value=""
  local state_rc=""
  local env_overrides_file=""

  # Validate input
  if [[ -z "${var_name}" ]]; then
    echo "${default_value}"
    return 1
  fi

  state_rc="$(state_rc_file)"
  env_overrides_file="$(state_env_overrides_file)"

  # Check staterc first (primary state file)
  if [[ -f "${state_rc}" ]]; then
    value="$(state_read_value_from_file "${state_rc}" "${var_name}")"
  fi

  # Fall back to env-overrides if not found
  if [[ -z "${value}" ]] && [[ -f "${env_overrides_file}" ]]; then
    value="$(state_read_value_from_file "${env_overrides_file}" "${var_name}")"
  fi

  # Return value or default
  echo "${value:-${default_value}}"
}

state_target_file() {
  case "${1:-staterc}" in
    staterc) state_rc_file ;;
    env-overrides) state_env_overrides_file ;;
    color_variant) state_color_variant_file ;;
    *) state_rc_file ;;
  esac
}

state_acquire_lock() {
  local target_file="$1"
  local fd_name="$2"
  local -n fd_ref="${fd_name}"
  local lock_timeout="${STATE_LOCK_TIMEOUT:-5}"
  local lock_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr"
  local lock_file="${lock_dir}/state-${target_file}.lock"

  mkdir -p "${lock_dir}" || return 1
  if ! exec {fd_ref}>"${lock_file}"; then
    print_log -sec "state" -err "state_set" "failed to open lock ${lock_file}"
    return 1
  fi

  if ! flock -w "${lock_timeout}" "${fd_ref}"; then
    print_log -sec "state" -warn "state_set" "lock busy (${lock_file})"
    exec {fd_ref}>&-
    fd_ref=""
    return 1
  fi
}

state_release_lock() {
  local fd_name="$1"
  local -n fd_ref="${fd_name}"

  [[ -n "${fd_ref:-}" ]] || return 0
  flock -u "${fd_ref}" 2>/dev/null || true
  exec {fd_ref}>&-
  fd_ref=""
}

state_write_color_variant_file() {
  local state_file="$1"
  local var_value="$2"
  local tmp_file="${state_file}.tmp"

  if [[ -z "${var_value}" ]]; then
    print_log -sec "state" -err "state_set" "color variant value required"
    return 1
  fi

  printf '%s\n' "${var_value}" >"${tmp_file}" && mv -f "${tmp_file}" "${state_file}"
}

state_quote_value() {
  local value="${1-}"

  if [[ "${value}" == *$'\n'* || "${value}" == *$'\r'* ]]; then
    print_log -sec "state" -err "state_set" "state values must be single-line"
    return 1
  fi

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\$}"
  value="${value//\`/\\\`}"
  printf '"%s"' "${value}"
}

state_write_key_value_file() {
  local state_file="$1"
  local target_file="$2"
  local var_name="$3"
  local var_value="$4"
  local tmp_file="${state_file}.tmp.$$"
  local var_escaped=""
  local value_prefix=""
  local quoted_value=""

  [[ -n "${var_name}" ]] || {
    print_log -sec "state" -err "state_set" "variable name required"
    return 1
  }

  touch "${state_file}"
  var_escaped="$(printf "%s" "${var_name}" | sed 's/[][\\.^$*+?()|{}]/\\&/g')"
  [[ "${target_file}" == "env-overrides" ]] && value_prefix="export "
  quoted_value="$(state_quote_value "${var_value}")" || return 1

  {
    grep -Ev "^(export[[:space:]]+)?${var_escaped}=" "${state_file}" 2>/dev/null || true
    printf '%s%s=%s\n' "${value_prefix}" "${var_name}" "${quoted_value}"
  } >"${tmp_file}"

  if mv -f "${tmp_file}" "${state_file}"; then
    return 0
  fi

  rm -f "${tmp_file}" 2>/dev/null
  print_log -sec "state" -err "state_set" "failed to write ${var_name}"
  return 1
}

# Set a state variable (atomic write to prevent race conditions)
# Usage: state_set VARIABLE_NAME value [file]
# file: "staterc" (default), "env-overrides", or "color_variant"
state_set() {
  local var_name="$1"
  local var_value="$2"
  local target_file="${3:-staterc}"
  local state_file=""
  local lock_fd=""
  local rc=0

  state_file="$(state_target_file "${target_file}")"
  mkdir -p "$(dirname "${state_file}")" || return 1
  state_acquire_lock "${target_file}" lock_fd || return 1

  if [[ "${target_file}" == "color_variant" ]]; then
    state_write_color_variant_file "${state_file}" "${var_value}" || rc=$?
    state_release_lock lock_fd
    return "${rc}"
  fi

  state_write_key_value_file "${state_file}" "${target_file}" "${var_name}" "${var_value}" || rc=$?
  state_release_lock lock_fd
  return "${rc}"
}

# Get the current resolved dark/light variant
# Returns: dark, light, or empty
state_get_color_variant() {
  local color_variant_file=""
  color_variant_file="$(state_color_variant_file)"

  if [[ -f "${color_variant_file}" ]]; then
    cat "${color_variant_file}" 2>/dev/null
  else
    echo "dark" # Default
  fi
}

# Set the current resolved dark/light variant
# Usage: state_set_color_variant dark|light
state_set_color_variant() {
  local color_variant="$1"
  if [[ ! "${color_variant}" =~ ^(dark|light)$ ]]; then
    print_log -sec "state" -err "state_set_color_variant" "invalid color variant '${color_variant}' (expected dark|light)"
    return 1
  fi
  state_set "" "${color_variant}" "color_variant"
}
