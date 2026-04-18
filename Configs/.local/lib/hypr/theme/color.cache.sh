#!/usr/bin/env bash
# shellcheck disable=SC2154

# Default cache directory
HYPR_WAL_CACHE_DIR="${HYPR_WAL_CACHE_DIR:-${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wal/cache}"

wal_cache_log() {
  local level="$1"
  local action="$2"
  local target="$3"
  local detail="${4:-}"
  local message="${action}: ${target}"

  if [[ -n "${detail}" ]]; then
    detail="${detail//$'\r'/ }"
    detail="${detail//$'\n'/; }"
    detail="${detail%; }"
    [[ -n "${detail}" ]] && message+=" (${detail})"
  fi

  if type print_log &>/dev/null; then
    case "${level}" in
      warn) print_log -sec "pywal16" -warn "cache" "${message}" ;;
      *) print_log -sec "pywal16" -err "cache" "${message}" ;;
    esac
  else
    printf 'pywal16 cache %s: %s\n' "${level}" "${message}" >&2
  fi
}

wal_cache_run_logged() {
  local level="$1"
  local action="$2"
  local target="$3"
  shift 3

  local output=""
  if output="$("$@" 2>&1)"; then
    return 0
  fi

  wal_cache_log "${level}" "${action}" "${target}" "${output}"
  return 1
}

wal_cache_remove_paths() {
  local level="$1"
  local action="$2"
  shift 2

  local path=""
  local label=""
  local -a existing_paths=()
  for path in "$@"; do
    [[ -e "${path}" || -L "${path}" ]] || continue
    existing_paths+=("${path}")
  done

  ((${#existing_paths[@]} > 0)) || return 0

  printf -v label '%s, ' "${existing_paths[@]}"
  label="${label%, }"
  wal_cache_run_logged "${level}" "${action}" "${label}" rm -rf -- "${existing_paths[@]}"
}

wal_cache_remove_paths_strict() {
  wal_cache_remove_paths err "$@"
}

wal_cache_remove_paths_warn() {
  wal_cache_remove_paths warn "$@"
}

wal_cache_move_path_strict() {
  local action="$1"
  local src="$2"
  local dest="$3"

  wal_cache_run_logged err "${action}" "${src} -> ${dest}" mv -- "${src}" "${dest}"
}

wal_cache_move_path_warn() {
  local action="$1"
  local src="$2"
  local dest="$3"

  wal_cache_run_logged warn "${action}" "${src} -> ${dest}" mv -- "${src}" "${dest}"
}

wal_cache_make_temp_dir() {
  local out_name="$1"
  local parent_dir="$2"
  local template="$3"
  local action="$4"
  local target="$5"
  local output=""

  if ! output="$(mktemp -d -p "${parent_dir}" "${template}" 2>&1)"; then
    wal_cache_log err "${action}" "${target}" "${output}"
    return 1
  fi

  # shellcheck disable=SC2178
  local -n out_ref="${out_name}"
  out_ref="${output}"
}

copy_entry_with_fallback() {
  local src="$1"
  local dest="$2"

  local output=""
  if output="$(cp -a --reflink=auto "${src}" "${dest}/" 2>&1)"; then
    return 0
  fi

  if output="$(cp -a "${src}" "${dest}/" 2>&1)"; then
    return 0
  fi

  wal_cache_log err "failed to copy cache entry" "${src} -> ${dest}" "${output}"
  return 1
}

copy_cache_tree() {
  local src_dir="$1"
  local dest_dir="$2"

  local output=""
  if output="$(cp -a --reflink=auto "${src_dir}/." "${dest_dir}/" 2>&1)"; then
    return 0
  fi

  if output="$(cp -a "${src_dir}/." "${dest_dir}/" 2>&1)"; then
    return 0
  fi

  wal_cache_log err "failed to copy cache tree" "${src_dir} -> ${dest_dir}" "${output}"
  return 1
}

create_backup_dir() {
  local parent_dir="$1"
  local dest_dir="$2"
  local backup_dir=""

  wal_cache_make_temp_dir backup_dir "${parent_dir}" "$(basename "${dest_dir}").bak.XXXXXXXX" \
    "failed to allocate cache backup dir" "${dest_dir}" || return 1
  wal_cache_remove_paths_strict "failed to prepare cache backup dir" "${backup_dir}" || return 1
  printf '%s\n' "${backup_dir}"
}

replace_dir_atomically() {
  local dest_dir="$1"
  local tmp_dir="$2"
  local backup_dir="$3"

  wal_cache_move_path_strict "failed to stage cache backup" "${dest_dir}" "${backup_dir}" || return 1
  wal_cache_move_path_strict "failed to promote cache staging dir" "${tmp_dir}" "${dest_dir}" || {
    wal_cache_move_path_warn "failed to restore cache backup after promote failure" "${backup_dir}" "${dest_dir}"
    return 1
  }

  wal_cache_remove_paths_warn "failed to remove obsolete cache backup" "${backup_dir}" || true
  return 0
}

preserve_wal_state() {
  local dest_dir="$1"
  local dest_parent="$2"

  schemes_tmp=""
  post_hooks_tmp=""
  if [[ -d "${dest_dir}/schemes" ]]; then
    schemes_tmp="$(mktemp -d -p "${dest_parent}" wal.schemes.XXXXXXXX)" || schemes_tmp=""
    if [[ -n "${schemes_tmp}" ]] && ! wal_cache_move_path_warn "failed to preserve wal schemes" "${dest_dir}/schemes" "${schemes_tmp}"; then
      schemes_tmp=""
    fi
  fi
  if [[ -f "${dest_dir}/post-hooks.sh" ]]; then
    post_hooks_tmp="$(mktemp -p "${dest_parent}" wal.post-hooks.XXXXXXXX)" || post_hooks_tmp=""
    if [[ -n "${post_hooks_tmp}" ]] && ! wal_cache_move_path_warn "failed to preserve wal post-hooks" "${dest_dir}/post-hooks.sh" "${post_hooks_tmp}"; then
      post_hooks_tmp=""
    fi
  fi

  return 0
}

restore_wal_state() {
  local dest_dir="$1"

  if [[ -n "${schemes_tmp:-}" ]] && [[ -d "${schemes_tmp}" ]]; then
    wal_cache_move_path_warn "failed to restore wal schemes" "${schemes_tmp}" "${dest_dir}/schemes"
  fi
  if [[ -n "${post_hooks_tmp:-}" ]] && [[ -f "${post_hooks_tmp}" ]]; then
    wal_cache_move_path_warn "failed to restore wal post-hooks" "${post_hooks_tmp}" "${dest_dir}/post-hooks.sh" || true
  fi

  return 0
}

write_cache_meta() {
  local tmp_dir="$1"

  {
    echo "${wal_cache_key}"
    echo "wallpaper=${STATE_WALLPAPER:-${WALLPAPER_IMAGE}}"
    echo "color_variant=${resolved_color_variant}"
    echo "backend=${PYWAL_BACKEND}"
  } >"${tmp_dir}/.meta"
  touch "${tmp_dir}/.complete"
}

cache_cleanup_stale() {
  local cache_dir="$1"
  local keep_suffix="$2"
  local dir base

  [[ -d "${cache_dir}" ]] || return 0

  while IFS= read -r -d '' dir; do
    base="${dir##*/}"
    case "${base}" in
      *.tmp.* | *.bak.*) continue ;;
    esac

    if ! wal_cache_valid "${dir}"; then
      wal_cache_remove_paths_warn "failed to prune invalid wal cache entry" "${dir}"
      continue
    fi

    if [[ -n "${keep_suffix}" ]] && [[ "${base}" != *"${keep_suffix}" ]]; then
      wal_cache_remove_paths_warn "failed to prune stale wal cache entry" "${dir}"
    fi
  done < <(find "${cache_dir}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
}

queue_cache_cleanup() {
  local cache_dir="$1"
  local keep_suffix="$2"
  local cache_cleanup_lock=""

  [[ "${CACHE_CLEANUP_ENABLED}" -eq 1 ]] || return 0
  [[ "${CACHE_ONLY}" -ne 1 ]] || return 0
  [[ -d "${cache_dir}" ]] || return 0
  cache_cleanup_lock="$(hypr_lock_path wal_cache_clean)"

  (
    exec 200>&- 201>&- 202>&- 203>&-
    exec 201>"${cache_cleanup_lock}"
    flock -n 201 || exit 0
    cache_cleanup_stale "${cache_dir}" "${keep_suffix}"
  ) &
  disown
}

queue_wal_cache_prune() {
  local wal_cache_prune_lock=""

  [[ "${WAL_CACHE_PRUNE_ENABLED}" -eq 1 ]] || return 0
  [[ "${CACHE_ONLY}" -ne 1 ]] || return 0
  [[ -d "${HYPR_WAL_CACHE_DIR}" ]] || return 0
  wal_cache_prune_lock="$(hypr_lock_path wal_cache_prune)"

  local ttl="${WAL_CACHE_PRUNE_TTL}"
  [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl=21600

  local stamp="${WAL_CACHE_PRUNE_STAMP}"
  local now last
  now="$(date +%s)"
  last=0
  if [[ -f "${stamp}" ]]; then
    last="$(cat "${stamp}" 2>/dev/null)"
    [[ "${last}" =~ ^[0-9]+$ ]] || last=0
  fi
  if [[ "${ttl}" -gt 0 ]] && (( now - last < ttl )); then
    return 0
  fi

  (
    exec 200>&- 201>&- 202>&- 203>&-
    exec 205>"${wal_cache_prune_lock}"
    flock -n 205 || exit 0

    local now_ts last_ts
    now_ts="$(date +%s)"
    last_ts=0
    if [[ -f "${stamp}" ]]; then
      last_ts="$(cat "${stamp}" 2>/dev/null)"
      [[ "${last_ts}" =~ ^[0-9]+$ ]] || last_ts=0
    fi
    if [[ "${ttl}" -gt 0 ]] && (( now_ts - last_ts < ttl )); then
      exit 0
    fi
    printf '%s\n' "${now_ts}" > "${stamp}.tmp" && mv -f "${stamp}.tmp" "${stamp}"

    local theme_root="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/themes"
    local dir base meta wallpaper theme_name
    while IFS= read -r -d '' dir; do
      base="${dir##*/}"
      case "${base}" in
        *.tmp.* | *.bak.*) continue ;;
      esac

      if ! wal_cache_valid "${dir}"; then
        wal_cache_remove_paths_warn "failed to prune invalid wal cache entry" "${dir}"
        continue
      fi

      meta="${dir}/.meta"
      if [[ ! -f "${meta}" ]]; then
        wal_cache_remove_paths_warn "failed to prune wal cache entry missing metadata" "${dir}"
        continue
      fi

      wallpaper="$(sed -n 's/^wallpaper=//p' "${meta}" | head -1)"
      if [[ -z "${wallpaper}" ]]; then
        wal_cache_remove_paths_warn "failed to prune wal cache entry missing wallpaper" "${dir}"
        continue
      fi

      case "${wallpaper}" in
        theme:*)
          theme_name="${wallpaper#theme:}"
          if [[ -n "${theme_name}" ]] && [[ -d "${theme_root}/${theme_name}" ]]; then
            continue
          fi
          wal_cache_remove_paths_warn "failed to prune wal cache entry for missing theme" "${dir}"
          continue
          ;;
        theme)
          continue
          ;;
      esac

      if [[ ! -e "${wallpaper}" ]]; then
        wal_cache_remove_paths_warn "failed to prune wal cache entry for missing wallpaper" "${dir}"
      fi
    done < <(find -H "${HYPR_WAL_CACHE_DIR}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  ) &
  disown
}

wal_cache_valid() {
  local dir="${1}"

  # Validate input
  [[ -z "${dir}" ]] && return 1
  [[ ! -d "${dir}" ]] && return 1

  # Check required files exist
  [[ -f "${dir}/.complete" ]] || return 1
  [[ -f "${dir}/colors.json" ]] || return 1
  [[ -f "${dir}/colors-shell.sh" ]] || return 1

  return 0
}

wal_cache_swap_dir() {
  local src_dir="${1}"
  local dest_dir="${2}"

  # Validate inputs
  [[ -z "${src_dir}" ]] && return 1
  [[ -z "${dest_dir}" ]] && return 1
  [[ -d "${src_dir}" ]] || return 1

  local dest_parent tmp_dir backup_dir
  dest_parent="$(dirname "${dest_dir}")"
  mkdir -p "${dest_parent}"

  wal_cache_make_temp_dir tmp_dir "${dest_parent}" "wal.swap.XXXXXXXX" \
    "failed to create wal cache swap dir" "${dest_dir}" || return 1
  copy_cache_tree "${src_dir}" "${tmp_dir}" || {
    wal_cache_remove_paths_warn "failed to clean wal cache swap dir after copy failure" "${tmp_dir}"
    return 1
  }
  wal_cache_remove_paths_strict "failed to strip cache markers from wal cache swap dir" \
    "${tmp_dir}/.complete" "${tmp_dir}/.meta" || {
    wal_cache_remove_paths_warn "failed to clean wal cache swap dir after marker cleanup failure" "${tmp_dir}"
    return 1
  }

  if [[ -e "${dest_dir}" ]] && [[ ! -d "${dest_dir}" ]]; then
    wal_cache_remove_paths_strict "failed to remove non-directory wal cache target" "${dest_dir}" || {
      wal_cache_remove_paths_warn "failed to clean wal cache swap dir after target cleanup failure" "${tmp_dir}"
      return 1
    }
  fi

  if [[ -d "${dest_dir}" ]]; then
    preserve_wal_state "${dest_dir}" "${dest_parent}"
    backup_dir="$(create_backup_dir "${dest_parent}" "${dest_dir}")" || {
      restore_wal_state "${dest_dir}"
      wal_cache_remove_paths_warn "failed to clean wal cache swap dir after backup allocation failure" "${tmp_dir}"
      return 1
    }
    replace_dir_atomically "${dest_dir}" "${tmp_dir}" "${backup_dir}" || {
      restore_wal_state "${dest_dir}"
      wal_cache_remove_paths_warn "failed to clean wal cache swap dir after replace failure" "${tmp_dir}"
      return 1
    }
    restore_wal_state "${dest_dir}"
  else
    wal_cache_move_path_strict "failed to install wal cache swap dir" "${tmp_dir}" "${dest_dir}" || {
      wal_cache_remove_paths_warn "failed to clean wal cache swap dir after install failure" "${tmp_dir}"
      return 1
    }
  fi
}

wal_cache_store() {
  local src_dir="${1}"
  local dest_dir="${2}"

  # Validate inputs
  [[ -z "${src_dir}" ]] && return 1
  [[ -z "${dest_dir}" ]] && return 1
  [[ -d "${src_dir}" ]] || return 1

  local dest_parent tmp_dir backup_dir entry
  dest_parent="$(dirname "${dest_dir}")"
  wal_cache_run_logged err "failed to create wal cache parent dir" "${dest_parent}" mkdir -p -- "${dest_parent}" || return 1

  wal_cache_make_temp_dir tmp_dir "${dest_parent}" "$(basename "${dest_dir}").tmp.XXXXXXXX" \
    "failed to create wal cache staging dir" "${dest_dir}" || return 1

  while IFS= read -r -d '' entry; do
    copy_entry_with_fallback "${entry}" "${tmp_dir}" || {
      wal_cache_remove_paths_warn "failed to clean wal cache staging dir after copy failure" "${tmp_dir}"
      return 1
    }
  done < <(
    find "${src_dir}" -mindepth 1 -maxdepth 1 \
      ! -name "schemes" \
      ! -name "post-hooks.sh" \
      -print0 2>/dev/null
  )

  write_cache_meta "${tmp_dir}"

  if [[ -d "${dest_dir}" ]]; then
    backup_dir="$(create_backup_dir "${dest_parent}" "${dest_dir}")" || {
      wal_cache_remove_paths_warn "failed to clean wal cache staging dir after backup allocation failure" "${tmp_dir}"
      return 1
    }
    replace_dir_atomically "${dest_dir}" "${tmp_dir}" "${backup_dir}" || {
      wal_cache_remove_paths_warn "failed to clean wal cache staging dir after replace failure" "${tmp_dir}"
      return 1
    }
  else
    wal_cache_move_path_strict "failed to install wal cache staging dir" "${tmp_dir}" "${dest_dir}" || {
      wal_cache_remove_paths_warn "failed to clean wal cache staging dir after install failure" "${tmp_dir}"
      return 1
    }
  fi

  type print_log &>/dev/null && print_log -sec "pywal16" -stat "cache" "stored"
}

wal_cache_store_with_lock() {
  local src_dir="$1"
  local dest_dir="$2"
  local cache_store_fd=""
  local cache_store_lock=""

  cache_store_lock="$(hypr_lock_path wal_cache_store)"
  exec {cache_store_fd}>"${cache_store_lock}"
  flock "${cache_store_fd}"
  wal_cache_store "${src_dir}" "${dest_dir}"
  local store_exit=$?
  flock -u "${cache_store_fd}" 2>/dev/null || true
  exec {cache_store_fd}>&-
  return "${store_exit}"
}

wal_cache_store_async() {
  local src_dir="$1"
  local dest_dir="$2"
  local cache_key="${wal_cache_key}"
  local state_wallpaper="${STATE_WALLPAPER:-${WALLPAPER_IMAGE}}"
  local color_variant="${resolved_color_variant}"
  local backend="${PYWAL_BACKEND}"

  (
    exec 200>&- 201>&- 202>&- 203>&-
    [[ -d "${src_dir}" ]] || exit 0
    [[ -f "${src_dir}/colors.json" ]] || exit 0

    wal_cache_key="${cache_key}"
    STATE_WALLPAPER="${state_wallpaper}"
    resolved_color_variant="${color_variant}"
    PYWAL_BACKEND="${backend}"
    wal_cache_store_with_lock "${src_dir}" "${dest_dir}" || exit 0
  ) &
  disown
}
