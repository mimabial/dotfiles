#!/usr/bin/env bash

set -euo pipefail

watcher_service="org.kde.StatusNotifierWatcher"
watcher_path="/StatusNotifierWatcher"

watcher_ready() {
  busctl --user tree "${watcher_service}" 2>/dev/null | grep -q "${watcher_path}"
}

if watcher_ready; then
  if [[ "${1:-}" == "--" ]]; then
    shift
    exec "$@"
  fi
  exit 0
fi

qdbus6 org.kde.kded6 /kded org.kde.kded6.loadModule statusnotifierwatcher >/dev/null

for _ in {1..20}; do
  if watcher_ready; then
    if [[ "${1:-}" == "--" ]]; then
      shift
      exec "$@"
    fi
    exit 0
  fi
  sleep 0.1
done

printf '%s\n' "Failed to initialize StatusNotifierWatcher" >&2
exit 1
