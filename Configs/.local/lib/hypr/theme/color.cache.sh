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
#   dcol_mode       - Current color mode (dark/light)
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
    echo "wallpaper=${WALLPAPER_IMAGE}"
    echo "mode=${dcol_mode}"
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
  hash=$(${hashMech:-xxh64sum} "${wallpaper}" 2>/dev/null | cut -d' ' -f1)
  [[ -z "${hash}" ]] && return 1

  echo "${hash}_${mode}_${backend}"
}
