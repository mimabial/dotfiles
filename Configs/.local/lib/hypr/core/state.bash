#!/usr/bin/env bash

_hypr_state_dir="${BASH_SOURCE[0]%/*}"
[[ "${_hypr_state_dir}" != "${BASH_SOURCE[0]}" ]] || _hypr_state_dir=.
if ! declare -F hypr_ensure_runtime_dir_into >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_hypr_state_dir}/common.bash" || return 1 2>/dev/null || exit 1
fi
# shellcheck source=/dev/null
source "${_hypr_state_dir}/state-read.bash" || return 1 2>/dev/null || exit 1
unset _hypr_state_dir

STATE_COLOR_MODE_AUTO=1
STATE_COLOR_MODE_DARK=2
STATE_COLOR_MODE_LIGHT=3

state_color_mode_is_valid() {
  case "${1:-}" in
    "${STATE_COLOR_MODE_AUTO}" | "${STATE_COLOR_MODE_DARK}" | "${STATE_COLOR_MODE_LIGHT}") return 0 ;;
    *) return 1 ;;
  esac
}

state_resolve_color_source_into() {
  local -n color_source_ref="$1"
  local source="${2-}"
  local mode="${3-}"

  case "${source}" in
    theme | wallpaper)
      color_source_ref="${source}"
      ;;
    *)
      if state_color_mode_is_valid "${mode}"; then
        color_source_ref=wallpaper
      else
        color_source_ref=theme
      fi
      ;;
  esac
}

state_resolve_color_mode_into() {
  local -n color_mode_ref="$1"
  local mode="${2-}"
  local stored_variant=""

  if state_color_mode_is_valid "${mode}"; then
    color_mode_ref="${mode}"
    return 0
  fi
  state_get_color_variant_into stored_variant || true
  if [[ "${stored_variant}" == "light" ]]; then
    color_mode_ref="${STATE_COLOR_MODE_LIGHT}"
  else
    color_mode_ref="${STATE_COLOR_MODE_DARK}"
  fi
}

state_load_runtime_environment() {
  local state_root="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
  local state_rc_path="${STATE_RC:-${state_root}/staterc}"
  local env_overrides_path="${STATE_ENV_OVERRIDES:-${state_root}/env-overrides}"

  [[ -f "${state_rc_path}" ]] && source "${state_rc_path}"
  [[ -f "${env_overrides_path}" ]] && source "${env_overrides_path}"
  refresh_hypr_runtime_state
  return $?
}

refresh_hypr_runtime_state() {
  state_resolve_color_source_into selected_color_source "${selected_color_source:-}" "${selected_color_mode:-}"
  state_resolve_color_mode_into selected_color_mode "${selected_color_mode:-}"

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
    if declare -F print_log >/dev/null 2>&1; then
      print_log -sec "theme" -warn "state" "theme dir missing: ${HYPR_THEME}"
    else
      printf 'WARN: theme dir missing: %s\n' "${HYPR_THEME}" >&2
    fi
  fi
  refresh_hypr_instance_signature
  export HYPR_THEME HYPR_THEME_DIR selected_color_source selected_color_mode HYPRLAND_INSTANCE_SIGNATURE
}

refresh_hypr_instance_signature() {
  local runtime_dir="${HYPR_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-}/hypr}"
  local candidate=""
  local candidate_count=0
  local candidate_path=""

  [[ -n "${runtime_dir}" && -d "${runtime_dir}" ]] || return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -S "${runtime_dir}/${HYPRLAND_INSTANCE_SIGNATURE}/.socket.sock" ]] && return 0
  unset HYPRLAND_INSTANCE_SIGNATURE

  for candidate_path in "${runtime_dir}"/*; do
    [[ -d "${candidate_path}" && ! -L "${candidate_path}" && "${candidate_path##*/}" != wallcache ]] || continue
    [[ -S "${candidate_path}/.socket.sock" ]] || continue
    candidate="${candidate_path##*/}"
    candidate_count=$((candidate_count + 1))
    HYPRLAND_INSTANCE_SIGNATURE="${candidate}"
    [[ "${candidate_count}" -gt 1 ]] && break
  done

  if [[ "${candidate_count}" -ne 1 ]]; then
    unset HYPRLAND_INSTANCE_SIGNATURE
  fi
}

# Readers are lock-free; writers replace complete files under a shared lock.

state_dir() {
  printf '%s\n' "${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
}

state_target_file_into() {
  local -n target_file_ref="$1"
  local state_root="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"

  case "${2:-staterc}" in
    env-overrides) target_file_ref="${STATE_ENV_OVERRIDES:-${state_root}/env-overrides}" ;;
    color_variant) target_file_ref="${STATE_COLOR_VARIANT:-${state_root}/color_variant}" ;;
    *) target_file_ref="${STATE_RC:-${state_root}/staterc}" ;;
  esac
}

state_rc_file() {
  local state_file=""

  state_target_file_into state_file staterc
  printf '%s\n' "${state_file}"
}

state_lock_file() {
  local out_name="$1" lock_label="${2##*/}" lock_dir=""

  lock_label="${lock_label//[^A-Za-z0-9._-]/_}"
  hypr_ensure_runtime_dir_into lock_dir hypr || return 1
  printf -v "${out_name}" '%s/state-%s.lock' "${lock_dir}" "${lock_label:-state}"
}

state_acquire_lock() {
  local lock_target="$1"
  local fd_name="$2"
  local -n fd_ref="${fd_name}"
  local lock_timeout="${STATE_LOCK_TIMEOUT:-5}"
  local lock_file=""

  state_lock_file lock_file "${lock_target}" || return 1

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
  exec {fd_ref}>&-
  fd_ref=""
}

state_write_color_variant_file() {
  local state_file="$1"
  local var_value="$2"
  local tmp_file="${state_file}.tmp" stored_variant=""

  if [[ -z "${var_value}" ]]; then
    print_log -sec "state" -err "state_set" "color variant value required"
    return 1
  fi
  [[ -r "${state_file}" ]] && IFS= read -r stored_variant <"${state_file}"
  [[ "${stored_variant}" != "${var_value}" ]] || return 0

  (
    trap 'rm -f "${tmp_file}" 2>/dev/null' EXIT HUP INT TERM
    printf '%s\n' "${var_value}" >"${tmp_file}"
    mv -f "${tmp_file}" "${state_file}" && trap - EXIT
  )
}

state_quote_value() {
  local out_name="$1" value="${2-}"

  if [[ "${value}" == *$'\n'* || "${value}" == *$'\r'* ]]; then
    print_log -sec "state" -err "state_set" "state values must be single-line"
    return 1
  fi

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\$}"
  value="${value//\`/\\\`}"
  printf -v "${out_name}" '"%s"' "${value}"
}

state_write_key_value_file() {
  local state_file="$1"
  local target_kind="$2"
  local var_name="$3"
  local var_value="$4"
  local tmp_file="" source_file="${state_file}" value_prefix="" quoted_value="" line="" candidate="" stored_value=""
  local -a stored_raw_values=() other_lines=()

  [[ "${var_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
    print_log -sec "state" -err "state_set" "invalid variable name '${var_name}'"
    return 1
  }

  [[ "${target_kind}" == "env-overrides" ]] && value_prefix="export "
  state_quote_value quoted_value "${var_value}" || return 1

  [[ -f "${source_file}" ]] || source_file=/dev/null
  while IFS= read -r line || [[ -n "${line}" ]]; do
    candidate="${line#"${line%%[![:space:]]*}"}"
    if [[ "${candidate}" =~ ^export[[:space:]]+ ]]; then
      candidate="${candidate:${#BASH_REMATCH[0]}}"
    fi
    if [[ "${candidate}" == "${var_name}="* ]]; then
      stored_raw_values+=("${candidate#"${var_name}="}")
    else
      other_lines+=("${line}")
    fi
  done <"${source_file}"
  if ((${#stored_raw_values[@]} == 1)); then
    state_decode_raw_value stored_value "${stored_raw_values[0]}"
    [[ "${stored_value}" != "${var_value}" ]] || return 0
  fi

  tmp_file="$(mktemp "${state_file}.tmp.XXXXXX")" || {
    print_log -sec "state" -err "state_set" "failed to allocate temp file for ${var_name}"
    return 1
  }
  if (
    trap 'rm -f "${tmp_file}" 2>/dev/null' EXIT HUP INT TERM
    {
      ((${#other_lines[@]} == 0)) || printf '%s\n' "${other_lines[@]}"
      printf '%s%s=%s\n' "${value_prefix}" "${var_name}" "${quoted_value}"
    } >"${tmp_file}"
    mv -f "${tmp_file}" "${state_file}" && trap - EXIT
  ); then
    return 0
  fi

  rm -f "${tmp_file}" 2>/dev/null
  print_log -sec "state" -err "state_set" "failed to write ${var_name}"
  return 1
}

state_set() {
  local var_name="$1"
  local var_value="$2"
  local target_kind="${3:-staterc}"
  local state_file=""
  local lock_fd="" state_parent="" rc=0

  state_target_file_into state_file "${target_kind}"
  state_parent="${state_file%/*}"
  [[ "${state_parent}" != "${state_file}" ]] || state_parent=.
  [[ -d "${state_parent}" ]] || mkdir -p "${state_parent}" || return 1
  state_acquire_lock "${state_file}" lock_fd || return 1

  if [[ "${target_kind}" == "color_variant" ]]; then
    state_write_color_variant_file "${state_file}" "${var_value}" || rc=$?
  else
    state_write_key_value_file "${state_file}" "${target_kind}" "${var_name}" "${var_value}" || rc=$?
  fi
  state_release_lock lock_fd
  return "${rc}"
}

state_get_color_variant_into() {
  local -n stored_variant_ref="$1"
  local state_root="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
  local color_variant_file="${STATE_COLOR_VARIANT:-${state_root}/color_variant}"

  stored_variant_ref=dark
  [[ -f "${color_variant_file}" ]] || return 0
  stored_variant_ref=""
  [[ -r "${color_variant_file}" ]] || return 1
  IFS= read -r stored_variant_ref <"${color_variant_file}" || true
}

state_resolve_color_variant_into() {
  local -n color_variant_ref="$1"

  case "${2-}" in
    "${STATE_COLOR_MODE_DARK}") color_variant_ref=dark ;;
    "${STATE_COLOR_MODE_LIGHT}") color_variant_ref=light ;;
    *)
      state_get_color_variant_into color_variant_ref || true
      [[ "${color_variant_ref}" =~ ^(dark|light)$ ]] || color_variant_ref=dark
      ;;
  esac
}

state_set_color_variant() {
  local color_variant="$1"
  if [[ ! "${color_variant}" =~ ^(dark|light)$ ]]; then
    print_log -sec "state" -err "state_set_color_variant" "invalid color variant '${color_variant}' (expected dark|light)"
    return 1
  fi
  state_set "" "${color_variant}" "color_variant"
}
