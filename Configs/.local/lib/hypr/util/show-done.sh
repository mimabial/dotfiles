#!/usr/bin/env bash

set -euo pipefail

if [[ -t 1 ]]; then
  echo
  echo "Done. Press any key to close."
  read -r -n 1 _ </dev/tty || true
fi
