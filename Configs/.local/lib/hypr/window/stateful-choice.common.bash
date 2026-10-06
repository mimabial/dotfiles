#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

hypr_stateful_choice_resolve_path() {
  local name="$1"
  local extension="$2"
  local user_dir="$3"
  local shared_dir="$4"
  local candidate=""

  name="${name%.${extension}}"
  if [[ "${name}" == */* ]] && [[ -f "${name}" ]]; then
    printf '%s\n' "${name}"
    return 0
  fi

  for candidate in \
    "${user_dir}/${name}.${extension}" \
    "${shared_dir}/${name}.${extension}"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

hypr_stateful_choice_list_names() {
  local extension="$1"
  local user_dir="$2"
  local shared_dir="$3"
  shift 3
  local dir=""
  local path=""
  local name=""
  local skip_name=""
  local -A seen=()
  local -A skip=()

  for skip_name in "$@"; do
    skip["${skip_name}"]=1
  done

  for dir in "${user_dir}" "${shared_dir}"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r -d '' path; do
      name="$(basename "${path}" ".${extension}")"
      [[ -n "${skip[${name}]:-}" || -n "${seen[${name}]:-}" ]] && continue
      seen["${name}"]=1
      printf '%s\n' "${name}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name "*.${extension}" -print0 | sort -z)
  done
}

# hypr_stateful_choice_write_lua <out-file> [--load <path>] [--config <key> <value>] <NAME=VALUE>...
# Writes the generated Lua fragment Hyprland picks up through runtime.load.
hypr_stateful_choice_write_lua() {
  local out_file="$1"
  shift
  local load_path="" config_key="" config_value="" entry=""
  local -a assignments=()

  while (($#)); do
    case "$1" in
      --load)
        load_path="$2"
        shift 2
        ;;
      --config)
        config_key="$2"
        config_value="$3"
        shift 3
        ;;
      *)
        assignments+=("$1")
        shift
        ;;
    esac
  done

  mkdir -p "$(dirname "${out_file}")" || return 1

  {
    printf '%s\n' '-- Generated native Hyprland Lua. Do not edit manually.'
    printf '%s\n' 'local runtime = require("runtime")'
    printf '%s\n\n' 'local vars = require("vars")'
    for entry in "${assignments[@]}"; do
      printf 'vars.set("%s", %s)\n' "${entry%%=*}" "$(hypr_lua_string "${entry#*=}")"
    done
    if [[ -n "${load_path}" ]]; then
      printf 'runtime.load(%s)\n' "$(hypr_lua_string "${load_path}")"
    fi
    if [[ -n "${config_key}" ]]; then
      printf 'runtime.config("%s", %s)\n' "${config_key}" "$(hypr_lua_string "${config_value}")"
    fi
  } >"${out_file}"
}

hypr_stateful_choice_apply() {
  local state_key="$1"
  local value="$2"
  local notify_tag="$3"
  local notify_title="$4"
  local update_fn="$5"

  state_set "${state_key}" "${value}" "staterc"
  "${update_fn}" "${value}"

  [[ "${HYPR_STATEFUL_CHOICE_QUIET:-0}" == 1 ]] && return 0
  send_ephemeral_notif "${notify_tag}" -t 2000 -i "preferences-desktop-display" "${notify_title}" "${value}"
}
