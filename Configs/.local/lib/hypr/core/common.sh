#!/usr/bin/env bash
# shellcheck disable=SC1091,SC1090

hypr_core_file() {
  local rel_path="$1"
  local shared_file="${HYPR_DATA_HOME}/${rel_path}"
  local user_file="${HYPR_CONFIG_HOME}/${rel_path}"

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

