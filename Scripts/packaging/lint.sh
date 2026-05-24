#!/usr/bin/env bash

set -e

scrDir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
# shellcheck disable=SC1091
source "${scrDir}/global_fn.sh" || exit 1

check_availability=0
quiet=0
manifest_files=()
errors=0
warnings=0

usage() {
    cat <<EOF
Usage: $0 [--availability] [--syntax-only] [manifest ...]

Checks package manifests for malformed rows, duplicate packages, invalid tokens,
missing dependency references, and optionally package availability.
EOF
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

lint_error() {
    errors=$((errors + 1))
    printf 'ERROR: %s\n' "$*" >&2
}

lint_warn() {
    warnings=$((warnings + 1))
    printf 'WARN: %s\n' "$*" >&2
}

valid_pkg_token() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9@._+-]*$ ]]
}

package_known() {
    local pkg="$1"

    pkg_installed "${pkg}" && return 0
    pacman -Si "${pkg}" >/dev/null 2>&1 && return 0
    command -v yay >/dev/null 2>&1 && yay -Si --aur "${pkg}" >/dev/null 2>&1 && return 0
    command -v paru >/dev/null 2>&1 && paru -Si --aur "${pkg}" >/dev/null 2>&1 && return 0
    [ -x "${pacmanCmd}" ] && "${pacmanCmd}" info "${pkg}" >/dev/null 2>&1 && return 0

    return 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --availability)
        check_availability=1
        shift
        ;;
    --syntax-only)
        check_availability=0
        shift
        ;;
    -q | --quiet)
        quiet=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    --)
        shift
        break
        ;;
    -*)
        lint_error "unknown option: $1"
        shift
        ;;
    *)
        manifest_files+=("$1")
        shift
        ;;
    esac
done

while [ "$#" -gt 0 ]; do
    manifest_files+=("$1")
    shift
done

if [ "${#manifest_files[@]}" -eq 0 ]; then
    manifest_files=("${scrDir}/pkg_core.lst")
fi

declare -A package_seen=()
declare -A package_source=()
declare -A dependency_refs=()

parse_manifest() {
    local manifest="$1"
    local raw line pipe_count pkg deps dep line_no=0

    if [ ! -f "${manifest}" ]; then
        lint_error "manifest not found: ${manifest}"
        return 0
    fi

    while IFS= read -r raw || [ -n "${raw}" ]; do
        line_no=$((line_no + 1))
        line="${raw%%#*}"
        line="$(trim "${line}")"
        [ -n "${line}" ] || continue

        pipe_count="${line//[^|]/}"
        if [ "${#pipe_count}" -gt 1 ]; then
            lint_error "${manifest}:${line_no}: expected at most one pipe separator"
            continue
        fi

        if [[ "${line}" == *"|"* ]]; then
            pkg="$(trim "${line%%|*}")"
            deps="$(trim "${line#*|}")"
        else
            pkg="$(trim "${line}")"
            deps=""
        fi

        if [ -z "${pkg}" ]; then
            lint_error "${manifest}:${line_no}: empty package name"
            continue
        fi
        if [[ "${pkg}" =~ [[:space:]] ]]; then
            lint_error "${manifest}:${line_no}: package name contains whitespace: ${pkg}"
            continue
        fi
        if ! valid_pkg_token "${pkg}"; then
            lint_error "${manifest}:${line_no}: invalid package token: ${pkg}"
            continue
        fi

        if [ -n "${package_seen[${pkg}]:-}" ]; then
            lint_error "${manifest}:${line_no}: duplicate package ${pkg}; first seen at ${package_source[${pkg}]}"
        else
            package_seen["${pkg}"]=1
            package_source["${pkg}"]="${manifest}:${line_no}"
        fi

        if [ -n "${deps}" ]; then
            for dep in ${deps}; do
                if ! valid_pkg_token "${dep}"; then
                    lint_error "${manifest}:${line_no}: invalid dependency token for ${pkg}: ${dep}"
                    continue
                fi
                dependency_refs["${dep}"]="${dependency_refs[${dep}]:+${dependency_refs[${dep}]}, }${pkg}"
            done
        fi
    done <"${manifest}"
}

for manifest in "${manifest_files[@]}"; do
    parse_manifest "${manifest}"
done

for dep in "${!dependency_refs[@]}"; do
    if [ -z "${package_seen[${dep}]:-}" ] && ! pkg_installed "${dep}"; then
        lint_warn "dependency ${dep} is referenced by ${dependency_refs[${dep}]} but is neither listed nor installed"
    fi
done

if [ "${check_availability}" -eq 1 ]; then
    for pkg in "${!package_seen[@]}"; do
        if ! package_known "${pkg}"; then
            lint_error "package not found in installed packages, pacman repos, or AUR helper: ${pkg}"
        fi
    done
fi

if [ "${quiet}" -ne 1 ]; then
    print_log -sec "lint" -stat "packages" "${#package_seen[@]} packages checked, ${warnings} warnings, ${errors} errors"
fi

[ "${errors}" -eq 0 ]
