#!/usr/bin/env bash

# Shared helpers for hypr service scripts.

hypr_service_default_root() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/hypr/default"
}

hypr_service_init() {
  if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
    local had_nounset=0
    if [[ "$-" == *u* ]]; then
      had_nounset=1
      set +u
    fi
    eval "$(hyprshell init)"
    if [[ "${had_nounset}" -eq 1 ]]; then
      set -u
    fi
  fi
}

hypr_service_die() {
  printf '%s\n' "$*" >&2
  exit 1
}

hypr_service_usage_refresh_config() {
  cat <<'USAGE'
Usage: hyprshell service/refresh-config.sh [--diff|--no-diff] [--quiet] <relative-path-under-config>
Example:
  hyprshell service/refresh-config.sh hypr/hyprlock.conf
USAGE
}

hypr_service_is_safe_relpath() {
  local rel_path="$1"
  [[ -n "${rel_path}" ]] || return 1
  [[ "${rel_path}" != /* ]] || return 1
  [[ "${rel_path}" != *".."* ]] || return 1
  return 0
}

hypr_service_template_path() {
  local rel_path="$1"
  printf '%s/%s\n' "$(hypr_service_default_root)" "${rel_path}"
}

hypr_service_shared_template_path() {
  local rel_path="$1"
  printf '%s/shared/%s\n' "$(hypr_service_default_root)" "${rel_path}"
}

hypr_service_has_template() {
  local rel_path="$1"
  local template_path
  template_path="$(hypr_service_template_path "${rel_path}")"
  [[ -f "${template_path}" ]]
}

hypr_service_has_shared_template() {
  local rel_path="$1"
  local template_path
  template_path="$(hypr_service_shared_template_path "${rel_path}")"
  [[ -f "${template_path}" ]]
}

hypr_service_apply_template() {
  local source_path="$1"
  local target_path="$2"
  local rel_path="$3"
  local show_diff="${4:-1}"
  local quiet="${5:-0}"
  local backup_path

  [[ -f "${source_path}" ]] || hypr_service_die "No template found for ${rel_path}: ${source_path}"

  mkdir -p "$(dirname "${target_path}")"

  backup_path=""
  if [[ -f "${target_path}" ]]; then
    backup_path="${target_path}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -f "${target_path}" "${backup_path}"
  fi

  cp -f "${source_path}" "${target_path}"

  if [[ -n "${backup_path}" ]] && cmp -s "${target_path}" "${backup_path}"; then
    rm -f "${backup_path}"
    [[ "${quiet}" -eq 1 ]] || printf 'Unchanged: %s\n' "${target_path}"
    return 0
  fi

  [[ "${quiet}" -eq 1 ]] || printf 'Refreshed: %s\n' "${target_path}"

  if [[ "${show_diff}" -eq 1 ]] && [[ -n "${backup_path}" ]] && [[ -f "${backup_path}" ]]; then
    printf 'Changes for %s:\n' "${rel_path}"
    diff -u "${backup_path}" "${target_path}" || true
  fi
}

hypr_service_refresh_config() {
  local rel_path="$1"
  local show_diff="${2:-1}"
  local quiet="${3:-0}"
  local source_path target_path

  if ! hypr_service_is_safe_relpath "${rel_path}"; then
    hypr_service_die "Invalid config path: ${rel_path}"
  fi

  source_path="$(hypr_service_template_path "${rel_path}")"
  target_path="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"
  hypr_service_apply_template "${source_path}" "${target_path}" "${rel_path}" "${show_diff}" "${quiet}"
}

hypr_service_refresh_shared() {
  local rel_path="$1"
  local show_diff="${2:-1}"
  local quiet="${3:-0}"
  local source_path target_path

  if ! hypr_service_is_safe_relpath "${rel_path}"; then
    hypr_service_die "Invalid shared path: ${rel_path}"
  fi

  source_path="$(hypr_service_shared_template_path "${rel_path}")"
  target_path="${XDG_DATA_HOME:-$HOME/.local/share}/${rel_path}"
  hypr_service_apply_template "${source_path}" "${target_path}" "${rel_path}" "${show_diff}" "${quiet}"
}

hypr_service_refresh_many() {
  local show_diff="$1"
  local quiet="$2"
  shift 2

  local rel_path
  for rel_path in "$@"; do
    hypr_service_refresh_config "${rel_path}" "${show_diff}" "${quiet}"
  done
}

hypr_service_refresh_shared_many() {
  local show_diff="$1"
  local quiet="$2"
  shift 2

  local rel_path
  for rel_path in "$@"; do
    hypr_service_refresh_shared "${rel_path}" "${show_diff}" "${quiet}"
  done
}
