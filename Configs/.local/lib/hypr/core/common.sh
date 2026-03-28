#!/usr/bin/env bash
# shellcheck disable=SC1091,SC1090

hypr_core_file() {
  local rel_path="$1"
  local config_home="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local data_home="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}"
  local shared_file="${data_home}/${rel_path}"
  local user_file="${config_home}/${rel_path}"

  if [[ -f "${shared_file}" ]]; then
    printf '%s\n' "${shared_file}"
  elif [[ -f "${user_file}" ]]; then
    printf '%s\n' "${user_file}"
  else
    # Prefer shared path as canonical target for new writes/read attempts.
    printf '%s\n' "${shared_file}"
  fi
}

hypr_variables_file() {
  hypr_core_file "variables.conf"
}

hypr_config_layer_files() {
  local config_home="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local data_home="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}"
  local variables_file="${data_home}/variables.conf"

  [[ -f "${variables_file}" ]] || variables_file="${config_home}/variables.conf"

  printf '%s\n' \
    "${config_home}/themes/theme.conf" \
    "${config_home}/userfonts.conf" \
    "${variables_file}"
}

hypr_config_value_from_layers() {
  local variable_key="${1#\$}"
  local file_path=""
  local raw_line=""
  local lhs=""
  local rhs=""
  local value=""

  [[ -n "${variable_key}" ]] || return 1

  while IFS= read -r file_path; do
    [[ -f "${file_path}" ]] || continue
    if [[ ! -r "${file_path}" ]]; then
      printf 'ERROR: cannot read Hypr config file: %s\n' "${file_path}" >&2
      continue
    fi

    while IFS= read -r raw_line; do
      [[ -n "${raw_line//[[:space:]]/}" ]] || continue
      [[ ! "${raw_line}" =~ ^[[:space:]]*# ]] || continue
      [[ "${raw_line}" == *=* ]] || continue

      lhs="${raw_line%%=*}"
      rhs="${raw_line#*=}"
      lhs="${lhs#"${lhs%%[![:space:]]*}"}"
      lhs="${lhs%"${lhs##*[![:space:]]}"}"
      [[ "${lhs}" == "\$${variable_key}" ]] || continue

      rhs="${rhs%%#*}"
      rhs="${rhs#"${rhs%%[![:space:]]*}"}"
      rhs="${rhs%"${rhs##*[![:space:]]}"}"
      rhs="${rhs%\'}"
      rhs="${rhs#\'}"
      rhs="${rhs%\"}"
      rhs="${rhs#\"}"

      if [[ -z "${rhs}" ]]; then
        printf 'WARN: invalid empty $%s in %s\n' "${variable_key}" "${file_path}" >&2
        break
      fi

      value="${rhs}"
      printf '%s\n' "${value}"
      return 0
    done < "${file_path}"
  done < <(hypr_config_layer_files)

  return 1
}

hypr_compact_path() {
  local path="$1"

  case "${path}" in
    "${XDG_CONFIG_HOME}"/*)
      printf '$XDG_CONFIG_HOME%s\n' "${path#${XDG_CONFIG_HOME}}"
      ;;
    "${XDG_DATA_HOME}"/*)
      printf '$XDG_DATA_HOME%s\n' "${path#${XDG_DATA_HOME}}"
      ;;
    "${XDG_STATE_HOME}"/*)
      printf '$XDG_STATE_HOME%s\n' "${path#${XDG_STATE_HOME}}"
      ;;
    "${XDG_CACHE_HOME}"/*)
      printf '$XDG_CACHE_HOME%s\n' "${path#${XDG_CACHE_HOME}}"
      ;;
    "${HOME}"/*)
      printf '$HOME%s\n' "${path#${HOME}}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}
