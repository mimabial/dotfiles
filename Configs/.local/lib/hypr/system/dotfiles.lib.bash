#!/usr/bin/env bash

HOST_PROFILE_STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/host-profile"
SYNC_MANIFEST_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/dotfiles-sync.conf"

host_profile_is_valid() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

sync_manifest_error() {
  printf '%s\n' "$1" >&2
  return 1
}

read_sync_manifest() {
  local -n records_ref="$1"
  local kind="" rel_path="" excludes="" extra=""

  [[ -r "${SYNC_MANIFEST_FILE}" ]] || sync_manifest_error "Sync manifest not found: ${SYNC_MANIFEST_FILE}" || return
  records_ref=()
  while IFS='|' read -r kind rel_path excludes extra; do
    [[ -n "${kind}${rel_path}${excludes}${extra}" && "${kind}" != \#* ]] || continue
    [[ -z "${extra}" && -n "${rel_path}" ]] \
      || sync_manifest_error "Invalid manifest entry: ${kind}|${rel_path}|${excludes}${extra:+|${extra}}" || return
    case "${rel_path}" in
      /* | *$'\r'*) sync_manifest_error "Manifest path must be relative and single-line: ${rel_path}" || return ;;
      .. | ../* | */../* | */..) sync_manifest_error "Manifest path must not contain '..' segments: ${rel_path}" || return ;;
    esac
    [[ "${kind}" =~ ^(dir|file|host)$ ]] || sync_manifest_error "Unknown manifest kind: ${kind}" || return
    records_ref+=("${kind}|${rel_path}|${excludes}")
  done <"${SYNC_MANIFEST_FILE}"
}

manifest_host_paths() {
  local -n host_records_ref="$1" host_paths_ref="$2"
  local record="" kind="" rel_path="" excludes=""

  host_paths_ref=()
  for record in "${host_records_ref[@]}"; do
    IFS='|' read -r kind rel_path excludes <<<"${record}"
    [[ "${kind}" == host ]] || continue
    host_paths_ref+=("${rel_path}")
  done
}
