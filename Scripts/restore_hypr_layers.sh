#!/usr/bin/env bash

set -euo pipefail

scrDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cfg_dir="${1:-${scrDir}/../Configs}"
theme_override="${2:-}"

exec "${scrDir}/restore_cfg.sh" "${scrDir}/restore_hypr_layers.psv" "${cfg_dir}" "${theme_override}"
