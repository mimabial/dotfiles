#!/usr/bin/env bash

set -euo pipefail

if pgrep -x hyprsunset >/dev/null 2>&1; then
  pkill -x hyprsunset >/dev/null 2>&1 || true
fi
uwsm-app -- hyprsunset >/dev/null 2>&1 &
