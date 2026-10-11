#!/usr/bin/env bash

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

state_get_into() {
  local out_name="$1"
  local var_name="${2:-}"
  local default_value="${3:-}"
  local state_root="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}"
  local state_file="" line="" stripped="" raw_value=""

  printf -v "${out_name}" '%s' "${default_value}"
  [[ -n "${var_name}" && "${var_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1

  for state_file in \
    "${STATE_ENV_OVERRIDES:-${state_root}/env-overrides}" \
    "${STATE_RC:-${state_root}/staterc}"; do
    [[ -f "${state_file}" ]] || continue
    while IFS= read -r line || [[ -n "${line}" ]]; do
      stripped="${line#"${line%%[![:space:]]*}"}"
      [[ "${stripped}" =~ ^(export[[:space:]]+)?${var_name}=(.*)$ ]] || continue
      raw_value="${BASH_REMATCH[2]}"
      [[ "${raw_value}" == \(* ]] && continue
      state_decode_raw_value "${out_name}" "${raw_value}"
      return 0
    done < "${state_file}"
  done
}

state_get() {
  local value=""
  local status=0

  state_get_into value "$@" || status=$?
  printf '%s\n' "${value}"
  return "${status}"
}
