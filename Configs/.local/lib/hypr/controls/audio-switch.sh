#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "$(command -v hyprshell)" || exit 1

exec "${LIB_DIR}/hypr/controls/volume-control.sh" -t
