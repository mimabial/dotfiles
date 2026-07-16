#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

_hypr_state_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F hypr_runtime_subdir >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_hypr_state_dir}/common.sh" || return 1 2>/dev/null || exit 1
fi
unset _hypr_state_dir

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
  return $?
}

refresh_hypr_runtime_state() {
  # Keep derived theme/runtime paths in sync after reloading state.
  case "${selected_color_mode:-}" in
    0 | 1 | 2 | 3) ;;
    *) selected_color_mode=0 ;;
  esac

  if [[ -z "${HYPR_THEME:-}" ]]; then
    if declare -F print_log >/dev/null 2>&1; then
      print_log -sec "theme" -err "state" "HYPR_THEME is not set"
    else
      printf 'ERROR: HYPR_THEME is not set\n' >&2
    fi
    return 1
  fi

  HYPR_THEME_DIR="${HYPR_CONFIG_HOME}/themes/${HYPR_THEME}"
  if [[ ! -d "${HYPR_THEME_DIR}" ]]; then
    # The saved theme references a directory that no longer exists (renamed,
    # moved, or deleted). Warn but keep going: the theme menu and recovery
    # paths must still run so the user can pick a new theme. Consumers that
    # require a valid theme dir (color.plan.sh, theme.switch.sh) do their own
    # check and surface their own error.
    if declare -F print_log >/dev/null 2>&1; then
      print_log -sec "theme" -warn "state" "theme dir missing: ${HYPR_THEME}"
    else
      printf 'WARN: theme dir missing: %s\n' "${HYPR_THEME}" >&2
    fi
  fi
  refresh_hypr_instance_signature
  export HYPR_THEME HYPR_THEME_DIR selected_color_mode HYPRLAND_INSTANCE_SIGNATURE
}

refresh_hypr_instance_signature() {
  local runtime_dir="${HYPR_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-}/hypr}"
  local candidate=""
  local candidate_count=0
  local candidate_path=""

  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && return 0
  [[ -n "${runtime_dir}" && -d "${runtime_dir}" ]] || return 0

  while IFS= read -r -d '' candidate_path; do
    [[ -S "${candidate_path}/.socket.sock" ]] || continue
    candidate="${candidate_path##*/}"
    candidate_count=$((candidate_count + 1))
    HYPRLAND_INSTANCE_SIGNATURE="${candidate}"
    [[ "${candidate_count}" -gt 1 ]] && break
  done < <(
    find "${runtime_dir}" -mindepth 1 -maxdepth 1 -type d ! -name wallcache -print0 2>/dev/null
  )

  if [[ "${candidate_count}" -ne 1 ]]; then
    unset HYPRLAND_INSTANCE_SIGNATURE
  fi
}

# UNIFIED STATE MANAGEMENT
# All state is stored as scalar key=value entries in these files:
#   - staterc:        User/runtime state (HYPR_THEME, selected_color_mode, etc.)
#   - env-overrides:  Exported environment overrides
#   - color_variant:  Current resolved dark/light variant
#
# Readers are lock-free. Writes use tmp+mv under flock, so readers see either
# the previous complete file or the next complete file; concurrent writers may
# still make a single read observe old values until the in-process cache refreshes.
#
# Use these functions for consistent state access across all scripts:
#   state_get  - Read a state variable
#   state_set  - Write a state variable (atomic)
#   state_get_color_variant - Read the resolved dark/light variant
#   state_set_color_variant - Write the resolved dark/light variant

declare -gA HYPR_STATE_CACHE_VALUES=()
declare -g HYPR_STATE_CACHE_SIGNATURE=""
declare -g HYPR_STATE_CACHE_READY=0

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

state_decode_raw_value() {
  local raw_value="${1-}"

  if [[ "${raw_value}" == \(* ]]; then
    if declare -F print_log >/dev/null 2>&1; then
      print_log -sec "state" -warn "state_get" "array syntax is unsupported"
    fi
    return 1
  fi

  if [[ ${#raw_value} -ge 2 && "${raw_value:0:1}" == '"' && "${raw_value:${#raw_value}-1:1}" == '"' ]]; then
    raw_value="${raw_value:1:${#raw_value}-2}"
    raw_value="${raw_value//\\\"/\"}"
    raw_value="${raw_value//\\\$/\$}"
    raw_value="${raw_value//\\\`/\`}"
    raw_value="${raw_value//\\\\/\\}"
    printf '%s' "${raw_value}"
    return 0
  fi

  if [[ ${#raw_value} -ge 2 && "${raw_value:0:1}" == "'" && "${raw_value:${#raw_value}-1:1}" == "'" ]]; then
    printf '%s' "${raw_value:1:${#raw_value}-2}"
    return 0
  fi

  printf '%s' "${raw_value}"
}

state_file_signature() {
  local state_file="$1"

  if [[ -e "${state_file}" || -L "${state_file}" ]]; then
    stat -Lc '%n:%y:%s:%i' -- "${state_file}" 2>/dev/null || printf '%s:unreadable\n' "${state_file}"
  else
    printf '%s:missing\n' "${state_file}"
  fi
}

state_parse_cache_file() {
  local state_file="$1"
  local line=""
  local stripped=""
  local raw_name=""
  local raw_value=""
  local value=""

  [[ -f "${state_file}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    stripped="${line#"${line%%[![:space:]]*}"}"
    [[ -n "${stripped}" ]] || continue
    [[ "${stripped}" == \#* ]] && continue

    if [[ "${stripped}" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      raw_name="${BASH_REMATCH[1]}"
      raw_value="${BASH_REMATCH[2]}"
    elif [[ "${stripped}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      raw_name="${BASH_REMATCH[1]}"
      raw_value="${BASH_REMATCH[2]}"
    else
      continue
    fi

    [[ "${raw_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -v "HYPR_STATE_CACHE_VALUES[${raw_name}]" ]] && continue
    # Arrays are valid shell state for sourced environments, but this scalar
    # cache cannot represent them. Skip without warning so unrelated array
    # entries do not make every state_get call noisy.
    [[ "${raw_value}" == \(* ]] && continue
    value="$(state_decode_raw_value "${raw_value}")" || continue
    HYPR_STATE_CACHE_VALUES["${raw_name}"]="${value}"
  done < "${state_file}"
}

state_cache_load() {
  local state_rc=""
  local env_overrides_file=""
  local signature=""

  state_rc="$(state_rc_file)"
  env_overrides_file="$(state_env_overrides_file)"
  signature="$(
    state_file_signature "${state_rc}"
    state_file_signature "${env_overrides_file}"
  )"

  if [[ "${HYPR_STATE_CACHE_READY:-0}" -eq 1 && "${HYPR_STATE_CACHE_SIGNATURE:-}" == "${signature}" ]]; then
    return 0
  fi

  HYPR_STATE_CACHE_VALUES=()
  state_parse_cache_file "${state_rc}"
  state_parse_cache_file "${env_overrides_file}"
  HYPR_STATE_CACHE_SIGNATURE="${signature}"
  HYPR_STATE_CACHE_READY=1
}

state_cache_invalidate() {
  HYPR_STATE_CACHE_VALUES=()
  HYPR_STATE_CACHE_SIGNATURE=""
  HYPR_STATE_CACHE_READY=0
}

# Get a state variable value
# Usage: state_get VARIABLE_NAME [default_value]
# Checks: staterc, env-overrides, then returns default
state_get() {
  local var_name="$1"
  local default_value="${2:-}"

  # Validate input
  if [[ -z "${var_name}" || ! "${var_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    printf '%s\n' "${default_value}"
    return 1
  fi

  if state_cache_load && [[ -v "HYPR_STATE_CACHE_VALUES[${var_name}]" ]]; then
    printf '%s\n' "${HYPR_STATE_CACHE_VALUES[${var_name}]}"
  else
    printf '%s\n' "${default_value}"
  fi
}

state_target_file() {
  case "${1:-staterc}" in
    staterc) state_rc_file ;;
    env-overrides) state_env_overrides_file ;;
    color_variant) state_color_variant_file ;;
    *) state_rc_file ;;
  esac
}

state_lock_name() {
  local lock_target="$1"
  local lock_label="${lock_target//[^A-Za-z0-9._-]/_}"
  local lock_checksum=""

  lock_checksum="$(printf '%s' "${lock_target}" | cksum | awk '{print $1}')" || return 1
  printf 'state-%s-%s.lock\n' "${lock_label:-state}" "${lock_checksum}"
}

state_acquire_lock() {
  local lock_target="$1"
  local fd_name="$2"
  local -n fd_ref="${fd_name}"
  local lock_timeout="${STATE_LOCK_TIMEOUT:-5}"
  local lock_dir=""
  local lock_name=""
  local lock_file=""

  lock_name="$(state_lock_name "${lock_target}")" || return 1
  lock_dir="$(hypr_runtime_subdir hypr)" || return 1
  lock_file="${lock_dir}/${lock_name}"

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
  local tmp_file=""
  local var_escaped=""
  local value_prefix=""
  local quoted_value=""

  [[ -n "${var_name}" ]] || {
    print_log -sec "state" -err "state_set" "variable name required"
    return 1
  }

  touch "${state_file}" || {
    print_log -sec "state" -err "state_set" "failed to access ${state_file}"
    return 1
  }
  var_escaped="$(printf "%s" "${var_name}" | sed 's/[][\\.^$*+?()|{}]/\\&/g')"
  [[ "${target_file}" == "env-overrides" ]] && value_prefix="export "
  quoted_value="$(state_quote_value "${var_value}")" || return 1
  tmp_file="$(mktemp "${state_file}.tmp.XXXXXX")" || {
    print_log -sec "state" -err "state_set" "failed to allocate temp file for ${var_name}"
    return 1
  }

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
  state_acquire_lock "${state_file}" lock_fd || return 1

  if [[ "${target_file}" == "color_variant" ]]; then
    state_write_color_variant_file "${state_file}" "${var_value}" || rc=$?
    [[ "${rc}" -eq 0 ]] && state_cache_invalidate
    state_release_lock lock_fd
    return "${rc}"
  fi

  state_write_key_value_file "${state_file}" "${target_file}" "${var_name}" "${var_value}" || rc=$?
  [[ "${rc}" -eq 0 ]] && state_cache_invalidate
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
