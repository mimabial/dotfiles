#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# State reader for indicator scripts that need to be cheap (Python startup
# costs ~80 ms, too slow for waybar modules with interval=1).
#
# Sibling readers — see waybar/STATE.md for the canonical format:
#   - waybar_state.get_state_value         (Python, staterc, mgmt path)
#   - waybar_watch.read_runtime_meta       (Python, lock-meta files)

waybar_state_init() {
  if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
    if ! eval "$(hyprshell init 2>/dev/null)"; then
      export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
      export HYPR_STATE_HOME="${XDG_STATE_HOME}/hypr"
    fi
  fi

  WAYBAR_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  WAYBAR_STATERC_FILE="${WAYBAR_STATE_HOME}/hypr/staterc"
  WAYBAR_ENV_OVERRIDES_FILE="${WAYBAR_STATE_HOME}/hypr/env-overrides"
  export WAYBAR_STATE_HOME WAYBAR_STATERC_FILE WAYBAR_ENV_OVERRIDES_FILE
}

waybar_state_value() {
  local var_name="$1"
  local default_value="${2:-}"
  local state_file=""
  local line=""
  local stripped=""
  local raw_value=""
  local found=0

  if declare -F state_get >/dev/null 2>&1; then
    state_get "${var_name}" "${default_value}"
    return 0
  fi

  for state_file in "${WAYBAR_STATERC_FILE}" "${WAYBAR_ENV_OVERRIDES_FILE}"; do
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
    printf '%s\n' "${raw_value}"
  else
    printf '%s\n' "${default_value}"
  fi
}
