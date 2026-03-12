#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/service.lib.bash"

show_diff=1
quiet=0
rel_path=""

while (($#)); do
  case "$1" in
    -h | --help)
      hypr_service_usage_refresh_config
      exit 0
      ;;
    -q | --quiet)
      quiet=1
      ;;
    --diff)
      show_diff=1
      ;;
    --no-diff)
      show_diff=0
      ;;
    -*)
      hypr_service_die "Unknown option: $1"
      ;;
    *)
      if [[ -n "${rel_path}" ]]; then
        hypr_service_die "Only one config path is supported per call."
      fi
      rel_path="$1"
      ;;
  esac
  shift
done

if [[ -z "${rel_path}" ]]; then
  hypr_service_usage_refresh_config
  exit 2
fi

hypr_service_init
hypr_service_refresh_config "${rel_path}" "${show_diff}" "${quiet}"
