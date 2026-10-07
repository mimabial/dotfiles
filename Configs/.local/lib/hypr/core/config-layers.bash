#!/usr/bin/env bash

# First wins: the reverse of the order hyprland.lua applies these layers in.
# vars.lua resolves user-first, like the package.path hyprland.lua sets.
hypr_config_layer_files() {
  local config_home="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local data_home="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}"
  local vars_file="${config_home}/vars.lua"

  [[ -f "${vars_file}" ]] || vars_file="${data_home}/vars.lua"

  printf '%s\n' \
    "${config_home}/userprefs.lua" \
    "${config_home}/userfonts.lua" \
    "${config_home}/themes/theme.meta" \
    "${vars_file}"
}

declare -gA HYPR_CONFIG_LAYER_CACHE=()
declare -g HYPR_CONFIG_LAYER_CACHE_KEY=""
declare -g HYPR_CONFIG_LAYER_CACHE_READY=0

hypr_config_file_signature_line() {
  local file_path="$1"

  if [[ -e "${file_path}" || -L "${file_path}" ]]; then
    stat -Lc '%n:%y:%s:%i' -- "${file_path}" 2>/dev/null || printf '%s:unreadable\n' "${file_path}"
  else
    printf '%s:missing\n' "${file_path}"
  fi
}

# shellcheck disable=SC2120
hypr_config_file_signature() {
  local file_path=""

  if (($#)); then
    for file_path in "$@"; do
      hypr_config_file_signature_line "${file_path}"
    done
    return 0
  fi

  while IFS= read -r file_path; do
    hypr_config_file_signature_line "${file_path}"
  done < <(hypr_config_layer_files)
}

hypr_config_parse_layer_file() {
  local file_path="$1"
  local -n layer_values_ref="$2"
  local raw_line=""
  local lhs=""
  local rhs=""
  local variable_key=""
  local vars_set_re='^[[:space:]]*vars\.set\("([^"]+)",[[:space:]]*"([^"]*)"\)'
  local vars_table_field_re='^[[:space:]]*(\["([^"]+)"\]|([A-Za-z_][A-Za-z0-9_]*))[[:space:]]*=[[:space:]]*"([^"]*)",?[[:space:]]*$'
  local is_vars_table=0

  [[ "${file_path##*/}" != vars.lua ]] || is_vars_table=1

  [[ -f "${file_path}" ]] || return 0
  if [[ ! -r "${file_path}" ]]; then
    printf 'ERROR: cannot read Hypr config file: %s\n' "${file_path}" >&2
    return 0
  fi

  while IFS= read -r raw_line; do
    [[ -n "${raw_line//[[:space:]]/}" ]] || continue
    [[ ! "${raw_line}" =~ ^[[:space:]]*# ]] || continue
    if [[ "${raw_line}" =~ ${vars_set_re} ]]; then
      variable_key="${BASH_REMATCH[1]}"
      rhs="${BASH_REMATCH[2]}"
    elif ((is_vars_table)) && [[ "${raw_line}" =~ ${vars_table_field_re} ]]; then
      variable_key="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
      rhs="${BASH_REMATCH[4]}"
    else
      [[ "${raw_line}" == *=* ]] || continue
      lhs="${raw_line%%=*}"
      rhs="${raw_line#*=}"
      lhs="${lhs#"${lhs%%[![:space:]]*}"}"
      lhs="${lhs%"${lhs##*[![:space:]]}"}"
      [[ "${lhs}" == \$* ]] || continue
      variable_key="${lhs#\$}"
      [[ -n "${variable_key}" ]] || continue

      rhs="${rhs%%#*}"
      rhs="${rhs#"${rhs%%[![:space:]]*}"}"
      rhs="${rhs%"${rhs##*[![:space:]]}"}"
      rhs="${rhs%\'}"
      rhs="${rhs#\'}"
      rhs="${rhs%\"}"
      rhs="${rhs#\"}"
    fi

    [[ -n "${rhs}" ]] || continue
    [[ -v "layer_values_ref[${variable_key}]" ]] && continue
    layer_values_ref["${variable_key}"]="${rhs}"
  done < "${file_path}"
}

hypr_config_layer_cache_load() {
  local cache_key=""
  local file_path=""

  # shellcheck disable=SC2119
  cache_key="$(hypr_config_file_signature)"
  if [[ "${HYPR_CONFIG_LAYER_CACHE_READY:-0}" -eq 1 && "${HYPR_CONFIG_LAYER_CACHE_KEY:-}" == "${cache_key}" ]]; then
    return 0
  fi

  HYPR_CONFIG_LAYER_CACHE=()
  while IFS= read -r file_path; do
    hypr_config_parse_layer_file "${file_path}" HYPR_CONFIG_LAYER_CACHE
  done < <(hypr_config_layer_files)

  HYPR_CONFIG_LAYER_CACHE_KEY="${cache_key}"
  HYPR_CONFIG_LAYER_CACHE_READY=1
}

hypr_config_value_from_layers() {
  local variable_key="${1#\$}"

  [[ -n "${variable_key}" ]] || return 1
  hypr_config_layer_cache_load || return 1
  [[ -v "HYPR_CONFIG_LAYER_CACHE[${variable_key}]" ]] || return 1
  printf '%s\n' "${HYPR_CONFIG_LAYER_CACHE[${variable_key}]}"

  return 0
}
