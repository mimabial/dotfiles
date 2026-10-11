#!/usr/bin/env bash

wallcache_outputs_are_ready() {
  local hash="${1}"
  [[ -n "${hash}" ]] || return 1
  [[ -e "${WALLPAPER_THUMB_DIR}/${hash}.thmb" ]] \
    && [[ -e "${WALLPAPER_THUMB_DIR}/${hash}.sqre" ]] \
    && [[ -e "${WALLPAPER_THUMB_DIR}/${hash}.blur" ]] \
    && [[ -e "${WALLPAPER_THUMB_DIR}/${hash}.quad" ]]
}

wallcache_requeue_job_file() {
  local source_job="$1"
  local job_name=""
  local target_job=""
  local wall_path=""
  local wall_hash=""

  [[ -f "${source_job}" ]] || return 0
  job_name="${source_job##*/}"
  target_job="${WALLCACHE_PENDING_DIR}/${job_name}"
  wall_hash="${job_name%.job}"
  IFS= read -r wall_path <"${source_job}" || true

  if [[ -n "${wall_hash}" ]] && wallcache_outputs_are_ready "${wall_hash}"; then
    rm -f -- "${source_job}"
    return 0
  fi
  if [[ -z "${wall_path}" ]] || [[ ! -f "${wall_path}" ]]; then
    rm -f -- "${source_job}"
    return 1
  fi
  if [[ -e "${target_job}" ]]; then
    rm -f -- "${source_job}"
    return 0
  fi

  mv -f -- "${source_job}" "${target_job}"
}

wallcache_recover_running_jobs() {
  local job_file=""
  local recovered=0

  while IFS= read -r -d '' job_file; do
    if wallcache_requeue_job_file "${job_file}"; then
      recovered=$((recovered + 1))
    fi
  done < <(find -H "${WALLCACHE_RUNNING_DIR}" -maxdepth 1 -type f -name "*.job" -print0 2>/dev/null)

  if (( recovered > 0 )); then
    print_log -sec "wallcache" -warn "recover" "requeued ${recovered} interrupted jobs"
  fi
}

wallcache_enqueue_wallpaper() {
  local wall="${1}"
  local resolved hash job_name job_pending job_running tmp_job

  [[ -n "${wall}" ]] || return 1
  resolved="$(
    readlink -f -- "${wall}" 2>/dev/null \
      || realpath -- "${wall}" 2>/dev/null \
      || printf '%s' "${wall}"
  )"
  [[ -f "${resolved}" ]] || return 1

  hash="$(wallpaper_file_hash "${resolved}" 2>/dev/null)" || return 1
  [[ -n "${hash}" ]] || return 1
  wallcache_outputs_are_ready "${hash}" && return 0

  job_name="${hash}.job"
  job_pending="${WALLCACHE_PENDING_DIR}/${job_name}"
  job_running="${WALLCACHE_RUNNING_DIR}/${job_name}"

  [[ -e "${job_pending}" ]] && return 0
  [[ -e "${job_running}" ]] && return 0

  tmp_job="${WALLCACHE_PENDING_DIR}/.${job_name}.$$"
  printf '%s\n' "${resolved}" >"${tmp_job}" || {
    rm -f "${tmp_job}" 2>/dev/null
    return 1
  }
  mv -n "${tmp_job}" "${job_pending}" 2>/dev/null || :
  rm -f "${tmp_job}" 2>/dev/null
  [[ -e "${job_running}" ]] && rm -f "${job_pending}" 2>/dev/null
  [[ -e "${job_pending}" || -e "${job_running}" ]] || wallcache_outputs_are_ready "${hash}"
}

wallcache_enqueue_theme() {
  local theme="${1}"
  local theme_dir=""
  local -a theme_hashes=()
  local -a theme_walls=()
  local wall

  [[ -n "${theme}" ]] || return 1
  if [[ -d "${theme}" ]]; then
    theme_dir="${theme}"
  elif [[ -d "${HYPR_THEME_DIR%/*}/${theme}" ]]; then
    theme_dir="${HYPR_THEME_DIR%/*}/${theme}"
  else
    return 1
  fi

  if ! wallpaper_scan_hashes_into theme_hashes theme_walls "${theme_dir}"; then
    return 0
  fi

  local enqueue_failed=0
  for wall in "${theme_walls[@]}"; do
    wallcache_enqueue_wallpaper "${wall}" || enqueue_failed=1
  done
  return "${enqueue_failed}"
}

wallcache_claim_batch() {
  local -n claim_args_ref="$1" claim_files_ref="$2"
  local job_file job_name running_file wall_path wall_hash

  claim_args_ref=()
  claim_files_ref=()
  while IFS= read -r -d '' job_file; do
    (( ${#claim_files_ref[@]} >= WALLCACHE_BATCH_MAX )) && break

    job_name="${job_file##*/}"
    running_file="${WALLCACHE_RUNNING_DIR}/${job_name}"
    mv -f "${job_file}" "${running_file}" 2>/dev/null || continue

    wall_path=""
    IFS= read -r wall_path <"${running_file}" || true
    wall_hash="${job_name%.job}"
    if [[ -z "${wall_path}" || ! -f "${wall_path}" || -z "${wall_hash}" ]] || wallcache_outputs_are_ready "${wall_hash}"; then
      rm -f "${running_file}"
      continue
    fi
    claim_args_ref+=(-w "${wall_path}")
    claim_files_ref+=("${running_file}")
  done < <(find -H "${WALLCACHE_PENDING_DIR}" -maxdepth 1 -type f -name "*.job" -print0 2>/dev/null | sort -z)
}

wallcache_run_batch() {
  local -n batch_args_ref="$1" batch_files_ref="$2"

  if "${WALLCACHE_WORKER_SCRIPT}" "${batch_args_ref[@]}" &>/dev/null; then
    rm -f -- "${batch_files_ref[@]}" 2>/dev/null || true
    return 0
  fi
  # A failed batch stays in running/, which this run never claims from, so an image
  # that always fails is retried once per daemon run (exit recovery requeues it),
  # not in a tight loop.
  print_log -sec "wallcache" -warn "batch" "cache generation failed; ${#batch_files_ref[@]} jobs retry on the next daemon run"
}
