#!/usr/bin/env bash

set -euo pipefail

scripts_dir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
# shellcheck disable=SC1091
source "${scripts_dir}/global_fn.sh" || exit 1

DOTFILES_LOG=${DOTFILES_LOG:-}
flg_DryRun=${flg_DryRun:-0}
flg_Nvidia=${flg_Nvidia:-1}
profile_file="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/host-profile"
profile=""

[[ -r "${profile_file}" ]] && IFS= read -r profile <"${profile_file}"

sudo_cmd=()
[[ "${EUID}" -eq 0 ]] || sudo_cmd=(sudo)

for system_dir in "${cloneDir}/Configs/.system" "${cloneDir}/Configs/hosts/${profile}/.system"; do
    [[ -d "${system_dir}" ]] || continue

    while IFS= read -r -d '' source_path; do
        target_path="/${source_path#"${system_dir}/"}"

        # This laptop reproduces NVIDIA UVM HMM allocation failures under game load.
        if [[ "${target_path}" == /etc/modprobe.d/uvm.conf && "${flg_Nvidia}" -ne 1 ]]; then
            print_log -sec "host system" -stat "skip" "${target_path}: NVIDIA actions disabled"
        elif cmp -s "${source_path}" "${target_path}"; then
            print_log -sec "host system" -stat "unchanged" "${target_path}"
        elif [[ "${flg_DryRun}" -eq 1 ]]; then
            print_log -sec "host system" -stat "dry-run" "install ${source_path} -> ${target_path}"
        else
            "${sudo_cmd[@]}" install -D -o root -g root -m 0644 "${source_path}" "${target_path}"
            print_log -sec "host system" -stat "installed" "${target_path}"
        fi
    done < <(find "${system_dir}" -type f -print0 | sort -z)
done
