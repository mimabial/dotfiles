#!/usr/bin/env bash

set -e

scrDir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
# shellcheck disable=SC1091
source "${scrDir}/global_fn.sh" || exit 1

flg_Install=${flg_Install:-0}
flg_Restore=${flg_Restore:-0}
flg_Service=${flg_Service:-0}
flg_DryRun=${flg_DryRun:-0}
custom_pkg=${custom_pkg:-}
errors=0
warnings=0

preflight_error() {
    errors=$((errors + 1))
    print_log -sec "preflight" -crit "error" "$*"
}

preflight_warn() {
    warnings=$((warnings + 1))
    print_log -sec "preflight" -warn "warning" "$*"
}

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        preflight_error "missing command: ${command_name}"
    fi
}

require_file() {
    local file_path="$1"
    if [ ! -f "${file_path}" ]; then
        preflight_error "missing file: ${file_path}"
    fi
}

require_dir() {
    local dir_path="$1"
    if [ ! -d "${dir_path}" ]; then
        preflight_error "missing directory: ${dir_path}"
    fi
}

check_sudo() {
    [ "${EUID}" -eq 0 ] && return 0

    if ! command -v sudo >/dev/null 2>&1; then
        preflight_error "sudo is required for install/service phases"
        return 0
    fi

    if [ "${flg_DryRun}" -eq 1 ]; then
        print_log -sec "preflight" -stat "sudo" "present"
        return 0
    fi

    if sudo -v; then
        print_log -sec "preflight" -stat "sudo" "validated"
    else
        preflight_error "sudo validation failed"
    fi
}

check_network_hint() {
    [ "${flg_Install}" -eq 1 ] || return 0
    [ "${flg_DryRun}" -eq 1 ] && return 0

    if command -v getent >/dev/null 2>&1 && getent hosts archlinux.org >/dev/null 2>&1; then
        print_log -sec "preflight" -stat "network" "DNS lookup succeeded"
    else
        preflight_warn "could not resolve archlinux.org; package installation may fail"
    fi
}

require_file "${scrDir}/global_fn.sh"

if [ "${flg_Install}" -eq 1 ]; then
    require_command pacman
    require_command git
    require_file "${scrDir}/pkg_core.lst"
    require_file "${scrDir}/install_pkg.sh"
    require_file "${scrDir}/install_aur.sh"
    require_file "${scrDir}/install_boot.sh"

    if [ -e /var/lib/pacman/db.lck ]; then
        preflight_error "pacman lock exists at /var/lib/pacman/db.lck"
    fi

    if [ -n "${custom_pkg}" ] && [ ! -f "${custom_pkg}" ]; then
        preflight_error "custom package manifest not found: ${custom_pkg}"
    fi

    lint_args=("--syntax-only" "${scrDir}/pkg_core.lst")
    [ -n "${custom_pkg}" ] && lint_args+=("${custom_pkg}")
    "${scrDir}/packaging/lint.sh" "${lint_args[@]}"
    check_sudo
    check_network_hint
fi

if [ "${flg_Restore}" -eq 1 ]; then
    require_dir "${cloneDir}/Configs"
    require_file "${scrDir}/restore_cfg.psv"
    require_file "${scrDir}/restore_cfg.sh"
    require_file "${scrDir}/restore_fnt.sh"
    require_file "${scrDir}/restore_thm.sh"
fi

if [ "${flg_Service}" -eq 1 ]; then
    require_command systemctl
    require_file "${scrDir}/restore_svc.lst"
    require_file "${scrDir}/restore_svc.sh"
    check_sudo
fi

if [ "${warnings}" -gt 0 ]; then
    print_log -sec "preflight" -warn "warnings" "${warnings} warning(s)"
fi

if [ "${errors}" -gt 0 ]; then
    print_log -sec "preflight" -crit "failed" "${errors} error(s)"
    exit 1
fi

print_log -sec "preflight" -stat "ok" "checks passed"
