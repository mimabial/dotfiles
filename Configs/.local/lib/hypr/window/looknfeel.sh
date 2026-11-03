#!/usr/bin/env bash
set -euo pipefail

exec "${BASH_SOURCE[0]%/*}/settings.sh" "$@"
