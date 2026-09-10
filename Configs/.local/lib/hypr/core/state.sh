#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

_hypr_state_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F hypr_runtime_subdir >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_hypr_state_dir}/common.sh" || return 1 2>/dev/null || exit 1
fi
unset _hypr_state_dir

state_resolve_color_source() {
  local source="${1-}"
  local mode="${2-}"

  case "${source}" in
    theme | pywal)
      printf '%s\n' "${source}"
      ;;
    *)
      case "${mode}" in
        1 | 2 | 3) printf 'pywal\n' ;;
        *) printf 'theme\n' ;;
      esac
      ;;
  esac
}

state_resolve_color_mode() {
  local mode="${1-}"
  local variant="${2-}"

  case "${mode}" in
    1 | 2 | 3)
      printf '%s\n' "${mode}"
      ;;
    *)
      [[ "${variant}" == "light" ]] && printf '3\n' || printf '2\n'
      ;;
  esac
}

export_hypr_config() {
  local state_root="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
  local user_conf_state="${STATE_RC:-${state_root}/staterc}"
  local user_conf="${STATE_ENV_OVERRIDES:-${state_root}/env-overrides}"

  [[ -f "${user_conf_state}" ]] && source "${user_conf_state}"
  [[ -f "${user_conf}" ]] && source "${user_conf}"
  refresh_hypr_runtime_state
  return $?
}

refresh_hypr_runtime_state() {
  selected_color_source="$(state_resolve_color_source "${selected_color_source:-}" "${selected_color_mode:-}")"
  selected_color_mode="$(state_resolve_color_mode "${selected_color_mode:-}" "${BACKGROUND_MODE:-}")"

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

state_rc_file() {
  printf '%s\n' "${STATE_RC:-${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/staterc}"
}

state_env_overrides_file() {
  printf '%s\n' "${STATE_ENV_OVERRIDES:-${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/env-overrides}"
}

state_color_variant_file() {
  printf '%s\n' "${STATE_COLOR_VARIANT:-${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/color_variant}"
}

state_decode_raw_value() {
  local out_name="$1" decoded="${2-}"

  if [[ ${#decoded} -ge 2 && "${decoded:0:1}" == '"' && "${decoded:${#decoded}-1:1}" == '"' ]]; then
    decoded="${decoded:1:${#decoded}-2}"
    decoded="${decoded//\\\"/\"}"
    decoded="${decoded//\\\$/\$}"
    decoded="${decoded//\\\`/\`}"
    decoded="${decoded//\\\\/\\}"
    printf -v "${out_name}" '%s' "${decoded}"
    return 0
  fi

  if [[ ${#decoded} -ge 2 && "${decoded:0:1}" == "'" && "${decoded:${#decoded}-1:1}" == "'" ]]; then
    printf -v "${out_name}" '%s' "${decoded:1:${#decoded}-2}"
    return 0
  fi

  printf -v "${out_name}" '%s' "${decoded}"
}

state_get() {
  local var_name="${1:-}"
  local default_value="${2:-}"
  local state_root="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
  local state_file="" line="" stripped="" raw_value="" value=""

  if [[ -z "${var_name}" || ! "${var_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    printf '%s\n' "${default_value}"
    return 1
  fi

  for state_file in \
    "${STATE_RC:-${state_root}/staterc}" \
    "${STATE_ENV_OVERRIDES:-${state_root}/env-overrides}"; do
    [[ -f "${state_file}" ]] || continue
    while IFS= read -r line || [[ -n "${line}" ]]; do
      stripped="${line#"${line%%[![:space:]]*}"}"
      [[ "${stripped}" =~ ^(export[[:space:]]+)?${var_name}=(.*)$ ]] || continue
      raw_value="${BASH_REMATCH[2]}"
      [[ "${raw_value}" == \(* ]] && continue
      state_decode_raw_value value "${raw_value}"
      printf '%s\n' "${value}"
      return 0
    done < "${state_file}"
  done
  printf '%s\n' "${default_value}"
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
  local lock_target="$1"
  local fd_name="$2"
  local -n fd_ref="${fd_name}"
  local lock_timeout="${STATE_LOCK_TIMEOUT:-5}"
  local lock_dir="" lock_label="${lock_target##*/}" lock_file=""

  # auto_theme_support.py derives the same basename-only lock key.
  lock_label="${lock_label//[^A-Za-z0-9._-]/_}"
  lock_dir="$(hypr_runtime_subdir hypr)" || return 1
  lock_file="${lock_dir}/state-${lock_label:-state}.lock"

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
  local tmp_file="${state_file}.tmp"

  if [[ -z "${var_value}" ]]; then
    print_log -sec "state" -err "state_set" "color variant value required"
    return 1
  fi

  (
    trap 'rm -f "${tmp_file}" 2>/dev/null' EXIT HUP INT TERM
    printf '%s\n' "${var_value}" >"${tmp_file}"
    mv -f "${tmp_file}" "${state_file}"
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
  local target_file="$2"
  local var_name="$3"
  local var_value="$4"
  local tmp_file="" source_file="${state_file}" value_prefix="" quoted_value="" line="" candidate=""

  [[ "${var_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
    print_log -sec "state" -err "state_set" "invalid variable name '${var_name}'"
    return 1
  }

  [[ "${target_file}" == "env-overrides" ]] && value_prefix="export "
  state_quote_value quoted_value "${var_value}" || return 1
  tmp_file="$(mktemp "${state_file}.tmp.XXXXXX")" || {
    print_log -sec "state" -err "state_set" "failed to allocate temp file for ${var_name}"
    return 1
  }

  [[ -f "${source_file}" ]] || source_file=/dev/null
  if (
    trap 'rm -f "${tmp_file}" 2>/dev/null' EXIT HUP INT TERM
    while IFS= read -r line || [[ -n "${line}" ]]; do
      candidate="${line#"${line%%[![:space:]]*}"}"
      if [[ "${candidate}" =~ ^export[[:space:]]+ ]]; then
        candidate="${candidate:${#BASH_REMATCH[0]}}"
      fi
      [[ "${candidate}" == "${var_name}="* ]] || printf '%s\n' "${line}"
    done <"${source_file}" >"${tmp_file}"
    printf '%s%s=%s\n' "${value_prefix}" "${var_name}" "${quoted_value}" >>"${tmp_file}"
    mv -f "${tmp_file}" "${state_file}"
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
  local target_file="${3:-staterc}"
  local state_file=""
  local lock_fd="" state_parent="" rc=0

  state_file="$(state_target_file "${target_file}")"
  state_parent="${state_file%/*}"
  [[ "${state_parent}" != "${state_file}" ]] || state_parent=.
  mkdir -p "${state_parent}" || return 1
  state_acquire_lock "${state_file}" lock_fd || return 1

  if [[ "${target_file}" == "color_variant" ]]; then
    state_write_color_variant_file "${state_file}" "${var_value}" || rc=$?
  else
    state_write_key_value_file "${state_file}" "${target_file}" "${var_name}" "${var_value}" || rc=$?
  fi
  state_release_lock lock_fd
  return "${rc}"
}

state_get_color_variant() {
  local state_root="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
  local color_variant_file="${STATE_COLOR_VARIANT:-${state_root}/color_variant}" value=""

  if [[ -f "${color_variant_file}" ]]; then
    [[ -r "${color_variant_file}" ]] || return 1
    IFS= read -r value <"${color_variant_file}" || true
    printf '%s\n' "${value}"
  else
    printf 'dark\n'
  fi
}

state_set_color_variant() {
  local color_variant="$1"
  if [[ ! "${color_variant}" =~ ^(dark|light)$ ]]; then
    print_log -sec "state" -err "state_set_color_variant" "invalid color variant '${color_variant}' (expected dark|light)"
    return 1
  fi
  state_set "" "${color_variant}" "color_variant"
}
