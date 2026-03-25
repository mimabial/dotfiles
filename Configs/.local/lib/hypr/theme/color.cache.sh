#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# color.cache.sh - Wallpaper color cache management
#
# OVERVIEW:
#   Manages the per-wallpaper color cache for pywal16. Caching allows instant
#   theme switching when returning to previously-used wallpapers.
#
# USAGE:
#   source color.cache.sh
#   wal_cache_valid "$cache_path" && echo "Cache hit"
#   wal_cache_swap_dir "$src" "$dest"
#   wal_cache_store "$wal_output" "$cache_path"
#
# DEPENDENCIES:
#   - HYPR_WAL_CACHE_DIR must be set (defaults provided)
#   - print_log function from globalcontrol.sh
#
# CACHE STRUCTURE:
#   $HYPR_WAL_CACHE_DIR/<wallpaper_hash>_<mode>_<backend>/
#     ├── colors.json        # Main color data
#     ├── colors-shell.sh    # Shell-sourceable colors
#     ├── .meta              # Cache metadata (key, wallpaper, mode, backend)
#     └── .complete          # Marker indicating valid cache

# Default cache directory
HYPR_WAL_CACHE_DIR="${HYPR_WAL_CACHE_DIR:-${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wal/cache}"

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
      rm -rf "${dir}" 2>/dev/null || true
      continue
    fi

    if [[ -n "${keep_suffix}" ]] && [[ "${base}" != *"${keep_suffix}" ]]; then
      rm -rf "${dir}" 2>/dev/null || true
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
        rm -rf -- "${dir}"
        continue
      fi

      meta="${dir}/.meta"
      if [[ ! -f "${meta}" ]]; then
        rm -rf -- "${dir}"
        continue
      fi

      wallpaper="$(sed -n 's/^wallpaper=//p' "${meta}" | head -1)"
      if [[ -z "${wallpaper}" ]]; then
        rm -rf -- "${dir}"
        continue
      fi

      case "${wallpaper}" in
        theme:*)
          theme_name="${wallpaper#theme:}"
          if [[ -n "${theme_name}" ]] && [[ -d "${theme_root}/${theme_name}" ]]; then
            continue
          fi
          rm -rf -- "${dir}"
          continue
          ;;
        theme)
          continue
          ;;
      esac

      if [[ ! -e "${wallpaper}" ]]; then
        rm -rf -- "${dir}"
      fi
    done < <(find -H "${HYPR_WAL_CACHE_DIR}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  ) &
  disown
}

# ============================================================================
# wal_cache_valid - Check if a cache directory contains valid color data
# ============================================================================
# Arguments:
#   $1 - Path to cache directory to validate
# Returns:
#   0 - Cache is valid and complete
#   1 - Cache is missing, incomplete, or corrupted
# Example:
#   if wal_cache_valid "$cache_path"; then
#     echo "Using cached colors"
#   fi
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

# ============================================================================
# wal_cache_swap_dir - Atomically swap cache directory contents
# ============================================================================
# Arguments:
#   $1 - Source directory (cached colors to restore)
#   $2 - Destination directory (active wal cache, e.g., ~/.cache/wal)
# Returns:
#   0 - Swap successful
#   1 - Swap failed (destination unchanged)
# Notes:
#   - Preserves schemes/ directory and post-hooks.sh from destination
#   - Uses atomic rename for crash safety
#   - Removes .complete and .meta markers from restored cache
wal_cache_swap_dir() {
  local src_dir="${1}"
  local dest_dir="${2}"

  # Validate inputs
  [[ -z "${src_dir}" ]] && return 1
  [[ -z "${dest_dir}" ]] && return 1
  [[ -d "${src_dir}" ]] || return 1

  local dest_parent tmp_dir backup_dir schemes_tmp post_hooks_tmp
  dest_parent="$(dirname "${dest_dir}")"
  mkdir -p "${dest_parent}"

  # Create temporary copy
  tmp_dir="$(mktemp -d -p "${dest_parent}" wal.swap.XXXXXXXX)" || return 1
  if ! cp -a --reflink=auto "${src_dir}/." "${tmp_dir}/" 2>/dev/null; then
    cp -a "${src_dir}/." "${tmp_dir}/" 2>/dev/null || {
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
  fi
  # Remove cache markers from restored content
  rm -f "${tmp_dir}/.complete" "${tmp_dir}/.meta" 2>/dev/null || true

  # Handle non-directory at destination
  if [[ -e "${dest_dir}" ]] && [[ ! -d "${dest_dir}" ]]; then
    rm -f "${dest_dir}" 2>/dev/null || true
  fi

  if [[ -d "${dest_dir}" ]]; then
    # Preserve wal history + user hooks across cache restores
    schemes_tmp=""
    post_hooks_tmp=""
    if [[ -d "${dest_dir}/schemes" ]]; then
      schemes_tmp="${dest_parent}/wal.schemes.$$"
      mv "${dest_dir}/schemes" "${schemes_tmp}" 2>/dev/null || schemes_tmp=""
    fi
    if [[ -f "${dest_dir}/post-hooks.sh" ]]; then
      post_hooks_tmp="${dest_parent}/wal.post-hooks.$$"
      mv "${dest_dir}/post-hooks.sh" "${post_hooks_tmp}" 2>/dev/null || post_hooks_tmp=""
    fi

    # Atomic swap with backup
    backup_dir="${dest_dir}.bak.$$"
    mv "${dest_dir}" "${backup_dir}" 2>/dev/null || {
      [[ -n "${schemes_tmp}" ]] && [[ -d "${schemes_tmp}" ]] && mv "${schemes_tmp}" "${dest_dir}/schemes" 2>/dev/null || true
      [[ -n "${post_hooks_tmp}" ]] && [[ -f "${post_hooks_tmp}" ]] && mv "${post_hooks_tmp}" "${dest_dir}/post-hooks.sh" 2>/dev/null || true
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
    mv "${tmp_dir}" "${dest_dir}" 2>/dev/null || {
      mv "${backup_dir}" "${dest_dir}" 2>/dev/null || true
      [[ -n "${schemes_tmp}" ]] && [[ -d "${schemes_tmp}" ]] && mv "${schemes_tmp}" "${dest_dir}/schemes" 2>/dev/null || true
      [[ -n "${post_hooks_tmp}" ]] && [[ -f "${post_hooks_tmp}" ]] && mv "${post_hooks_tmp}" "${dest_dir}/post-hooks.sh" 2>/dev/null || true
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }

    # Restore preserved content and cleanup
    [[ -n "${schemes_tmp}" ]] && [[ -d "${schemes_tmp}" ]] && mv "${schemes_tmp}" "${dest_dir}/schemes" 2>/dev/null || true
    [[ -n "${post_hooks_tmp}" ]] && [[ -f "${post_hooks_tmp}" ]] && mv "${post_hooks_tmp}" "${dest_dir}/post-hooks.sh" 2>/dev/null || true
    rm -rf "${backup_dir}" 2>/dev/null || true
  else
    mv "${tmp_dir}" "${dest_dir}" 2>/dev/null || {
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
  fi
}

# ============================================================================
# wal_cache_store - Persist pywal16 output to per-wallpaper cache
# ============================================================================
# Arguments:
#   $1 - Source directory (pywal16 output, e.g., ~/.cache/wal)
#   $2 - Destination cache path
# Global variables used:
#   wal_cache_key   - Cache key (wallpaper_hash_mode_backend)
#   WALLPAPER_IMAGE - Path to current wallpaper
#   resolved_color_variant       - Current resolved dark/light variant
#   PYWAL_BACKEND   - Pywal16 backend used
# Returns:
#   0 - Store successful
#   1 - Store failed
# Notes:
#   - Excludes schemes/ and post-hooks.sh from cache
#   - Writes .meta file with cache metadata
#   - Writes .complete marker on success
wal_cache_store() {
  local src_dir="${1}"
  local dest_dir="${2}"

  # Validate inputs
  [[ -z "${src_dir}" ]] && return 1
  [[ -z "${dest_dir}" ]] && return 1
  [[ -d "${src_dir}" ]] || return 1

  local dest_parent tmp_dir backup_dir
  dest_parent="$(dirname "${dest_dir}")"
  mkdir -p "${dest_parent}" 2>/dev/null || true

  # Create temporary directory for atomic write
  tmp_dir="$(mktemp -d -p "${dest_parent}" "$(basename "${dest_dir}").tmp.XXXXXXXX")" || return 1

  # Copy files (excluding schemes and post-hooks)
  while IFS= read -r -d '' entry; do
    if ! cp -a --reflink=auto "${entry}" "${tmp_dir}/" 2>/dev/null; then
      cp -a "${entry}" "${tmp_dir}/" 2>/dev/null || {
        rm -rf "${tmp_dir}" 2>/dev/null || true
        return 1
      }
    fi
  done < <(
    find "${src_dir}" -mindepth 1 -maxdepth 1 \
      ! -name "schemes" \
      ! -name "post-hooks.sh" \
      -print0 2>/dev/null
  )

  # Write metadata
  {
    echo "${wal_cache_key}"
    echo "wallpaper=${STATE_WALLPAPER:-${WALLPAPER_IMAGE}}"
    echo "color_variant=${resolved_color_variant}"
    echo "backend=${PYWAL_BACKEND}"
  } >"${tmp_dir}/.meta"
  touch "${tmp_dir}/.complete"

  # Atomic move to final location
  if [[ -d "${dest_dir}" ]]; then
    backup_dir="${dest_dir}.bak.$$"
    mv "${dest_dir}" "${backup_dir}" 2>/dev/null || {
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
    mv "${tmp_dir}" "${dest_dir}" 2>/dev/null || {
      mv "${backup_dir}" "${dest_dir}" 2>/dev/null || true
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
    rm -rf "${backup_dir}" 2>/dev/null || true
  else
    mv "${tmp_dir}" "${dest_dir}" 2>/dev/null || {
      rm -rf "${tmp_dir}" 2>/dev/null || true
      return 1
    }
  fi

  # Log success if print_log is available
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

# ============================================================================
# wal_cache_key_generate - Generate cache key for wallpaper
# ============================================================================
# Arguments:
#   $1 - Wallpaper path
#   $2 - Color mode (dark/light)
#   $3 - Pywal16 backend name
# Output:
#   Prints cache key to stdout
# Example:
#   key=$(wal_cache_key_generate "/path/to/wall.png" "dark" "wal")
wal_cache_key_generate() {
  local wallpaper="${1}"
  local mode="${2}"
  local backend="${3}"

  [[ -z "${wallpaper}" ]] && return 1
  [[ -z "${mode}" ]] && return 1
  [[ -z "${backend}" ]] && return 1

  local hash
  hash=$(${HYPR_HASH_COMMAND:-xxh64sum} "${wallpaper}" 2>/dev/null | cut -d' ' -f1)
  [[ -z "${hash}" ]] && return 1

  echo "${hash}_${mode}_${backend}"
}
