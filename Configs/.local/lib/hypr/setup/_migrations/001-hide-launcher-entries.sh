#!/usr/bin/env bash

set -euo pipefail

exec "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/setup/hide-launcher-entries.sh"
