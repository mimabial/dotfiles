#!/usr/bin/env bash

set -euo pipefail

pkill -x hyprsunset >/dev/null 2>&1 || true
uwsm-app -- hyprsunset >/dev/null 2>&1 &
