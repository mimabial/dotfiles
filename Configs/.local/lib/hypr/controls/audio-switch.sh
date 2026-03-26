#!/usr/bin/env bash

set -euo pipefail

scr_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"

exec "${scr_dir}/volume-control.sh" -t
