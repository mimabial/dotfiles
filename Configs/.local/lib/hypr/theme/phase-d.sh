#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Helpers for post-visible theme apply jobs.
#
# Phase D jobs are allowed to continue after theme.apply.sh returns. To avoid
# stale A->B->A writers committing old output, each job receives
# HYPR_THEME_APPLY_GENERATION and re-checks it under a per-writer lock
# immediately before promoting generated files into place.

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

if ! declare -F state_get >/dev/null 2>&1 || ! declare -F hypr_lock_path >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/hypr/runtime/init.bash" || return 1 2>/dev/null || exit 1
  hypr_runtime_require state lock_paths || return 1 2>/dev/null || exit 1
fi

theme_phase_d_generation="${HYPR_THEME_APPLY_GENERATION:-}"
theme_phase_d_lock_key="${HYPR_THEME_PHASE_D_LOCK_KEY:-}"
theme_phase_d_lock_fd=""

theme_phase_d_init() {
  theme_phase_d_lock_key="${1:-${theme_phase_d_lock_key}}"
  theme_phase_d_generation="${HYPR_THEME_APPLY_GENERATION:-${theme_phase_d_generation}}"
}

theme_phase_d_current_generation() {
  local current_generation=""

  [[ -n "${theme_phase_d_generation}" ]] || return 0
  current_generation="$(state_get "theme_apply_generation" "0" 2>/dev/null || printf '0')"
  [[ "${current_generation}" == "${theme_phase_d_generation}" ]]
}

theme_phase_d_acquire_lock() {
  local lock_path=""

  [[ -n "${theme_phase_d_lock_key}" ]] || return 0
  lock_path="$(hypr_lock_path "${theme_phase_d_lock_key}")" || return 1
  exec {theme_phase_d_lock_fd}>"${lock_path}" || return 1
  flock "${theme_phase_d_lock_fd}" || {
    exec {theme_phase_d_lock_fd}>&-
    theme_phase_d_lock_fd=""
    return 1
  }
}

theme_phase_d_release_lock() {
  [[ -n "${theme_phase_d_lock_fd:-}" ]] || return 0
  flock -u "${theme_phase_d_lock_fd}" 2>/dev/null || true
  exec {theme_phase_d_lock_fd}>&-
  theme_phase_d_lock_fd=""
}

theme_phase_d_promote_file() {
  local tmp_file="$1"
  local target_file="$2"
  local target_dir=""
  local rc=0

  [[ -n "${tmp_file}" && -n "${target_file}" ]] || return 1
  [[ -f "${tmp_file}" ]] || return 1
  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}" || {
    rm -f -- "${tmp_file}"
    return 1
  }

  theme_phase_d_acquire_lock || {
    rm -f -- "${tmp_file}"
    return 1
  }
  if ! theme_phase_d_current_generation; then
    rm -f -- "${tmp_file}"
    theme_phase_d_release_lock
    return 0
  fi

  if [[ -f "${target_file}" ]] && cmp -s "${tmp_file}" "${target_file}"; then
    rm -f -- "${tmp_file}" || rc=$?
  else
    mv -f -- "${tmp_file}" "${target_file}" || rc=$?
  fi

  theme_phase_d_release_lock
  return "${rc}"
}

theme_phase_d_promote_symlink() {
  local link_target="$1"
  local link_path="$2"
  local rc=0

  [[ -n "${link_target}" && -n "${link_path}" ]] || return 1
  mkdir -p "$(dirname "${link_path}")" || return 1

  theme_phase_d_acquire_lock || return 1
  if theme_phase_d_current_generation; then
    ln -sfn -- "${link_target}" "${link_path}" || rc=$?
  fi
  theme_phase_d_release_lock
  return "${rc}"
}

theme_phase_d_promote_dir() {
  local staging_dir="$1"
  local target_dir="$2"
  local rc=0

  [[ -n "${staging_dir}" && -n "${target_dir}" ]] || return 1
  [[ -d "${staging_dir}" ]] || return 1
  mkdir -p "$(dirname "${target_dir}")" || return 1

  theme_phase_d_acquire_lock || return 1
  if ! theme_phase_d_current_generation; then
    rm -rf -- "${staging_dir}"
    theme_phase_d_release_lock
    return 0
  fi

  rm -rf -- "${target_dir}" || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    mv -f -- "${staging_dir}" "${target_dir}" || rc=$?
  fi

  theme_phase_d_release_lock
  return "${rc}"
}

theme_phase_d_run_locked_if_current() {
  local rc=0

  theme_phase_d_acquire_lock || return 1
  if theme_phase_d_current_generation; then
    "$@" || rc=$?
  fi
  theme_phase_d_release_lock
  return "${rc}"
}
