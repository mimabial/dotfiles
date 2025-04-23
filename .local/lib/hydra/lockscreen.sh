#!/usr/bin/env bash

scrDir="$(dirname "$(realpath "$0")")"
# shellcheck source=$HOME/.local/lib/hydra/globalcontrol.sh
# shellcheck disable=SC1091
source "${scrDir}/globalcontrol.sh"
HYDRA_RUNTIME_DIR="${HYDRA_RUNTIME_DIR:-$XDG_RUNTIME_DIR/hydra}"
# shellcheck disable=SC1091
source "${HYDRA_RUNTIME_DIR}/environment"

"${LOCKSCREEN}" "${@}"
