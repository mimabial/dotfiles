#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state system || exit 1
hypr_runtime_load_state || exit 1

desktop_sync_lib="${LIB_DIR}/hypr/theme/lib/desktop.sync.bash"
if [[ ! -r "${desktop_sync_lib}" ]]; then
  print_log -sec "theme" -err "source" "missing ${desktop_sync_lib}"
  exit 1
fi

# shellcheck source=/dev/null
source "${desktop_sync_lib}" || exit 1

sync_mode="full"

while (($#)); do
  case "$1" in
    --full) sync_mode="full" ;;
    --static-only) sync_mode="static" ;;
    --runtime-only) sync_mode="runtime" ;;
    --quiet) THEME_DESKTOP_SYNC_LOG_DCONF=0 ;;
    *)
      echo "Usage: $(basename "$0") [--full|--static-only|--runtime-only] [--quiet]" >&2
      exit 1
      ;;
  esac
  shift
done

case "${sync_mode}" in
  full) theme_desktop_sync_full ;;
  static) theme_desktop_sync_static ;;
  runtime) theme_desktop_sync_runtime ;;
esac
