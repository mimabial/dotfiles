#!/usr/bin/env bash

set -e

scrDir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
# shellcheck disable=SC1091
source "${scrDir}/global_fn.sh" || exit 1

flg_Nvidia=${flg_Nvidia:-1}

nvidia_detect --verbose || true

if nvidia_detect; then
    if [ "${flg_Nvidia}" -eq 1 ]; then
        print_log -sec "hardware" -stat "nvidia" "driver detection enabled"
    else
        print_log -sec "hardware" -stat "nvidia" "detected but skipped by -n"
    fi
else
    print_log -sec "hardware" -stat "nvidia" "not detected"
fi
