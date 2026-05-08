#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# color.cache.sh - Helpers for the wal cache directory: read/write/move cache
# entries, prune by LRU, and atomically swap the active wal cache. Functions
# are namespaced wal_cache_* because the cache is the wal palette, not the
# generic theme cache.
#
# Subsystem inputs (set by color-sync.sh entrypoint via color.plan.sh):
#   resolved_color_variant, selected_color_mode, wal_cache_key
: "${resolved_color_variant-}" "${selected_color_mode-}" "${wal_cache_key-}"

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

  printf -v "${out_name}" '%s' "${output}"
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
  local now=""

  now="$(date +%s)"

  {
    echo "${wal_cache_key}"
    echo "mode=${selected_color_mode}"
    echo "wallpaper=${STATE_WALLPAPER:-${WALLPAPER_IMAGE}}"
    echo "color_variant=${resolved_color_variant}"
    echo "backend=${PYWAL_BACKEND}"
    echo "pipeline_input_hash=${PIPELINE_INPUT_HASH:-}"
    echo "created=${now}"
    echo "accessed=${now}"
  } >"${tmp_dir}/.meta"
  printf '%s\n' "${now}" >"${tmp_dir}/.accessed"
  touch "${tmp_dir}/.complete"
}

wal_cache_touch_access() {
  local dir="$1"
  local now=""

  [[ -d "${dir}" ]] || return 0
  now="$(date +%s)"
  printf '%s\n' "${now}" >"${dir}/.accessed" 2>/dev/null || true
  touch "${dir}" 2>/dev/null || true
}

wal_cache_entry_count() {
  local cache_dir="$1"

  find "${cache_dir}" -mindepth 1 -maxdepth 1 -type d \
    ! -name "*.tmp.*" \
    ! -name "*.bak.*" \
    -print 2>/dev/null | wc -l
}

wal_cache_total_bytes() {
  local cache_dir="$1"

  du -sb "${cache_dir}" 2>/dev/null | awk '{print $1}'
}

wal_cache_oldest_entry() {
  local cache_dir="$1"

  find "${cache_dir}" -mindepth 1 -maxdepth 1 -type d \
    ! -name "*.tmp.*" \
    ! -name "*.bak.*" \
    -printf '%T@ %p\n' 2>/dev/null \
    | LC_ALL=C sort -n \
    | awk 'NR == 1 {sub(/^[^ ]+ /, ""); print; exit}'
}

wal_cache_prune_lru() {
  local cache_dir="$1"
  local max_entries="${HYPR_WAL_CACHE_MAX_ENTRIES:-64}"
  local max_bytes="${HYPR_WAL_CACHE_MAX_BYTES:-33554432}"
  local entry_count=0
  local total_bytes=0
  local oldest=""

  [[ -d "${cache_dir}" ]] || return 0
  [[ "${max_entries}" =~ ^[0-9]+$ ]] || max_entries=64
  [[ "${max_bytes}" =~ ^[0-9]+$ ]] || max_bytes=33554432

  while :; do
    entry_count="$(wal_cache_entry_count "${cache_dir}")"
    total_bytes="$(wal_cache_total_bytes "${cache_dir}")"
    [[ -n "${total_bytes}" ]] || total_bytes=0

    if (( (max_entries == 0 || entry_count <= max_entries) && (max_bytes == 0 || total_bytes <= max_bytes) )); then
      break
    fi

    oldest="$(wal_cache_oldest_entry "${cache_dir}")"
    [[ -n "${oldest}" ]] || break
    wal_cache_remove_paths_warn "failed to prune old wal cache entry" "${oldest}" || break
  done
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

wal_cache_restore() {
  local src_dir="${1}"
  local dest_dir="${2}"

  [[ -n "${src_dir}" ]] || return 1
  [[ -n "${dest_dir}" ]] || return 1
  wal_cache_valid "${src_dir}" || return 1

  local dest_parent tmp_dir backup_dir=""
  dest_parent="$(dirname "${dest_dir}")"
  wal_cache_run_logged err "failed to create wal cache parent dir" "${dest_parent}" mkdir -p -- "${dest_parent}" || return 1

  wal_cache_make_temp_dir tmp_dir "${dest_parent}" "$(basename "${dest_dir}").tmp.XXXXXXXX" \
    "failed to create wal cache restore staging dir" "${dest_dir}" || return 1
  copy_cache_tree "${src_dir}" "${tmp_dir}" || {
    wal_cache_remove_paths_warn "failed to clean wal cache restore staging dir after copy failure" "${tmp_dir}"
    return 1
  }

  if [[ -d "${dest_dir}" ]]; then
    preserve_wal_state "${dest_dir}" "${dest_parent}"
    backup_dir="$(create_backup_dir "${dest_parent}" "${dest_dir}")" || {
      wal_cache_remove_paths_warn "failed to clean wal cache restore staging dir after backup allocation failure" "${tmp_dir}"
      restore_wal_state "${dest_dir}"
      return 1
    }
    replace_dir_atomically "${dest_dir}" "${tmp_dir}" "${backup_dir}" || {
      wal_cache_remove_paths_warn "failed to clean wal cache restore staging dir after replace failure" "${tmp_dir}"
      restore_wal_state "${dest_dir}"
      return 1
    }
    restore_wal_state "${dest_dir}"
  else
    wal_cache_move_path_strict "failed to install wal cache restore staging dir" "${tmp_dir}" "${dest_dir}" || {
      wal_cache_remove_paths_warn "failed to clean wal cache restore staging dir after install failure" "${tmp_dir}"
      return 1
    }
  fi

  wal_cache_touch_access "${src_dir}"
  type print_log &>/dev/null && print_log -sec "pywal16" -stat "cache" "restored"
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

  wal_cache_touch_access "${dest_dir}"
  wal_cache_prune_lru "${dest_parent}" >/dev/null 2>&1 || true
  type print_log &>/dev/null && print_log -sec "pywal16" -stat "cache" "stored"
}
