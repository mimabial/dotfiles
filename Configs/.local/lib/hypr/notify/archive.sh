#!/usr/bin/env bash
# Every command emits JSON for panel callers.
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

ARCHIVE_DEFAULT_LIMIT=200
ARCHIVE_DEFAULT_KEEP_DAYS=30
ARCHIVE_DEFAULT_MAX_ITEMS=1000
ARCHIVE_IMAGE_MAX_BYTES=$((12 * 1024 * 1024))
ARCHIVE_IMAGE_MAX_EDGE_PX=640
ARCHIVE_IMAGE_SHRINK_ONLY_GEOMETRY="${ARCHIVE_IMAGE_MAX_EDGE_PX}x${ARCHIVE_IMAGE_MAX_EDGE_PX}>"

usage() {
  cat <<USAGE
Usage: hyprshell notify/archive <command> [args]

  add                 archive the notification in the DUNST_* environment
  list [LIMIT]        the archive as JSON, newest first (default ${ARCHIVE_DEFAULT_LIMIT})
  remove KEY          drop one entry and any picture kept for it
  clear               drop all of them
  seen [MS]           read or set when the panel was last opened
  unread              how many arrived since then
  snapshot [LIMIT]    entries, unread count, and seen timestamp as JSON
  prune               apply the retention limits now

Retention and exclusions come from staterc:
  NOTIFY_KEEP_DAYS          days to keep         (default ${ARCHIVE_DEFAULT_KEEP_DAYS})
  NOTIFY_MAX_ITEMS          ceiling regardless   (default ${ARCHIVE_DEFAULT_MAX_ITEMS})
  NOTIFY_ARCHIVE_SKIP_APPS  '|'-separated app names
  NOTIFY_ARCHIVE_SKIP_TAGS  '|'-separated stack tags
USAGE
}

hypr_runtime_require state >/dev/null 2>&1 || true

archive_setting_into() { state_get_into "$1" "$2" "$3" 2>/dev/null || printf -v "$1" '%s' "$3"; }
archive_timestamp_ms_into() { printf -v "$1" '%s' "$((${EPOCHREALTIME/./} / 1000))"; }

source "${BASH_SOURCE[0]%/*}/lib/archive-storage.bash"
source "${BASH_SOURCE[0]%/*}/lib/archive-images.bash"
source "${BASH_SOURCE[0]%/*}/lib/archive-retention.bash"
source "${BASH_SOURCE[0]%/*}/lib/archive-commands.bash"

command="${1:-}"
(($#)) && shift
case "${command}" in
  -h | --help) usage ;;
  add) archive_add ;;
  list) archive_list "${1:-}" ;;
  remove) archive_remove "${1:-}" ;;
  clear) archive_clear ;;
  seen) archive_seen "${1:-}" ;;
  unread) archive_unread ;;
  snapshot) archive_snapshot "${1:-}" ;;
  prune)
    ensure_notification_archive
    if ! with_archive_lock prune_archive_locked; then
      printf '{"ok":false,"error":"archive rewrite failed"}\n'
      exit 1
    fi
    printf '{"ok":true,"pruned":true}\n'
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
