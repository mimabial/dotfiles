#!/usr/bin/env bash

set -euo pipefail

if pgrep -x swayosd-server >/dev/null 2>&1; then
  pkill -x swayosd-server >/dev/null 2>&1 || true
fi
uwsm-app -- swayosd-server >/dev/null 2>&1 &
