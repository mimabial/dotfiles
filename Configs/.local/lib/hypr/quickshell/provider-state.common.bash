#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
quickshell_state_init() {
  QUICKSHELL_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  QUICKSHELL_STATERC_FILE="${QUICKSHELL_STATE_HOME}/hypr/staterc"
  QUICKSHELL_ENV_OVERRIDES_FILE="${QUICKSHELL_STATE_HOME}/hypr/env-overrides"
  export QUICKSHELL_STATE_HOME QUICKSHELL_STATERC_FILE QUICKSHELL_ENV_OVERRIDES_FILE
}

quickshell_state_value() {
  local var_name="$1"
  local default_value="${2:-}"
  local destination="${3:-}"
  local state_file=""
  local line=""
  local stripped=""
  local raw_value=""
  local found=0

  if declare -F state_get >/dev/null 2>&1; then
    raw_value="$(state_get "${var_name}" "${default_value}")"
  else
    for state_file in "${QUICKSHELL_STATERC_FILE}" "${QUICKSHELL_ENV_OVERRIDES_FILE}"; do
      [[ -r "${state_file}" ]] || continue

      while IFS= read -r line || [[ -n "${line}" ]]; do
        stripped="${line#"${line%%[![:space:]]*}"}"
        [[ -n "${stripped}" ]] || continue
        [[ "${stripped}" == \#* ]] && continue

        case "${stripped}" in
          "export ${var_name}="*)
            raw_value="${stripped#"export ${var_name}="}"
            found=1
            ;;
          "${var_name}="*)
            raw_value="${stripped#"${var_name}="}"
            found=1
            ;;
          *)
            continue
            ;;
        esac
      done < "${state_file}"

      (( found )) && break
    done

    if (( found )); then
      raw_value="${raw_value%\"}"
      raw_value="${raw_value#\"}"
      raw_value="${raw_value%\'}"
      raw_value="${raw_value#\'}"
    else
      raw_value="${default_value}"
    fi
  fi
  if [[ -n "${destination}" ]]; then printf -v "${destination}" '%s' "${raw_value}"; else printf '%s\n' "${raw_value}"; fi
}
