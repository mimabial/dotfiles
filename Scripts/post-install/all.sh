#!/usr/bin/env bash

set -e

scrDir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
# shellcheck disable=SC1091
source "${scrDir}/global_fn.sh" || exit 1

run_step "post-install config" "${scrDir}/install_pst.sh"
