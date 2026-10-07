#!/usr/bin/env bash

hypr_help_guard() {
  local usage_text="${1:-}"
  shift || true

  local arg=""
  for arg in "$@"; do
    case "${arg}" in
      --) break ;;
      -h | --help)
        printf '%s\n' "${usage_text}"
        exit 0
        ;;
    esac
  done
}

hypr_compact_path() {
  local path="$1"
  local var_name=""
  local base_path=""

  for var_name in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME HOME; do
    base_path="${!var_name:-}"
    [[ -n "${base_path}" && "${path}" == "${base_path}"/* ]] || continue
    printf '$%s%s\n' "${var_name}" "${path#"${base_path}"}"
    return 0
  done

  printf '%s\n' "${path}"
}
