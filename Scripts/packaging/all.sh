#!/usr/bin/env bash

set -e

scrDir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
# shellcheck disable=SC1091
source "${scrDir}/global_fn.sh" || exit 1

flg_DryRun=${flg_DryRun:-0}
flg_Nvidia=${flg_Nvidia:-1}
custom_pkg="${1:-${custom_pkg:-}}"

archive_install_pkg_list() {
    local log_dir="${cacheDir}/logs/${HYDE_LOG:-manual}"
    if [ -f "${scrDir}/install_pkg.lst" ]; then
        mkdir -p "${log_dir}"
        mv -f "${scrDir}/install_pkg.lst" "${log_dir}/install_pkg.lst"
    fi
}

trap archive_install_pkg_list EXIT

cp "${scrDir}/pkg_core.lst" "${scrDir}/install_pkg.lst"
echo -e "\n#user packages" >>"${scrDir}/install_pkg.lst"

if [ -n "${custom_pkg}" ]; then
    cat "${custom_pkg}" >>"${scrDir}/install_pkg.lst"
    print_log -sec "package" -stat "custom" "added ${custom_pkg}"
fi

if nvidia_detect; then
    if [ "${flg_Nvidia}" -eq 1 ]; then
        for pkgbase in /usr/lib/modules/*/pkgbase; do
            [ -r "${pkgbase}" ] || continue
            while read -r kernel; do
                [ -n "${kernel}" ] && echo "${kernel}-headers" >>"${scrDir}/install_pkg.lst"
            done <"${pkgbase}"
        done
        nvidia_detect --drivers >>"${scrDir}/install_pkg.lst"
    else
        print_log -warn "Nvidia" "Nvidia GPU detected but ignored..."
    fi
fi

if ! grep -q "^#user packages" "${scrDir}/install_pkg.lst"; then
    print_log -sec "pkg" -crit "No user packages found..." "Log file at ${cacheDir}/logs/${HYDE_LOG:-manual}/install.sh"
    exit 1
fi

run_step "lint package manifest" "${scrDir}/packaging/lint.sh" --syntax-only "${scrDir}/install_pkg.lst"
run_step "install packages" "${scrDir}/install_pkg.sh" "${scrDir}/install_pkg.lst"
run_step "install bootloader" "${scrDir}/install_boot.sh"
