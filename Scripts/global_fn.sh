#!/usr/bin/env bash
set -e

scrDir="${HYDE_SCRIPTS_DIR:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")}"
cloneDir="${CLONE_DIR:-$(dirname "${scrDir}")}"
confDir="${XDG_CONFIG_HOME:-$HOME/.config}"
cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
aurList=(yay paru)
shlList=(zsh fish)
pacmanCmd=${cloneDir}/Configs/.local/lib/hypr/system/pm.sh

export HYDE_SCRIPTS_DIR="${scrDir}"
export cloneDir
export confDir
export cacheDir
export aurList
export shlList

pkg_installed() {
    pacman -Q "$1" &>/dev/null
}

chk_list() {
    vrType="$1"
    local inList=("${@:2}")
    for pkg in "${inList[@]}"; do
        if pkg_installed "${pkg}"; then
            printf -v "${vrType}" "%s" "${pkg}"
            # shellcheck disable=SC2163
            export "${vrType}"
            return 0
        fi
    done
    return 1
}

pkg_available() {
    "${pacmanCmd}" query "$1" &>/dev/null
}

aur_available() {
    "${pacmanCmd}" info "$1" &>/dev/null
}

prompt_timer() {
    unset PROMPT_INPUT
    local timsec=$1
    local msg=$2
    while [[ ${timsec} -ge 0 ]]; do
        echo -ne "\r :: ${msg} (${timsec}s) : "
        if read -rt 1 -n 1 PROMPT_INPUT; then break; fi
        timsec=$((timsec - 1))
    done
    export PROMPT_INPUT
    echo ""
}
print_log() {
    local executable="${0##*/}"
    local logFile="${cacheDir}/logs/${HYDE_LOG}/${executable}.log"
    mkdir -p "$(dirname "${logFile}")"
    local section=${log_section:-}
    {
        [ -n "${section}" ] && echo -ne "\e[32m[$section] \e[0m"
        while (("$#")); do
            case "$1" in
            -r | +r)
                echo -ne "\e[31m$2\e[0m"
                shift 2
                ;;
            -g | +g)
                echo -ne "\e[32m$2\e[0m"
                shift 2
                ;;
            -y | +y)
                echo -ne "\e[33m$2\e[0m"
                shift 2
                ;;
            -b | +b)
                echo -ne "\e[34m$2\e[0m"
                shift 2
                ;;
            -m | +m)
                echo -ne "\e[35m$2\e[0m"
                shift 2
                ;;
            -c | +c)
                echo -ne "\e[36m$2\e[0m"
                shift 2
                ;;
            -wt | +w)
                echo -ne "\e[37m$2\e[0m"
                shift 2
                ;;
            -n | +n)
                echo -ne "\e[96m$2\e[0m"
                shift 2
                ;;
            -stat)
                echo -ne "\e[30;46m $2 \e[0m :: "
                shift 2
                ;;
            -crit)
                echo -ne "\e[97;41m $2 \e[0m :: "
                shift 2
                ;;
            -warn)
                echo -ne "WARNING :: \e[30;43m $2 \e[0m :: "
                shift 2
                ;;
            +)
                echo -ne "\e[38;5;$2m$3\e[0m"
                shift 3
                ;;
            -sec)
                echo -ne "\e[32m[$2] \e[0m"
                shift 2
                ;;
            -err)
                echo -ne "ERROR :: \e[4;31m$2 \e[0m"
                shift 2
                ;;
            *)
                echo -ne "$1"
                shift
                ;;
            esac
        done
        echo ""
    } | if [ -n "${HYDE_LOG}" ]; then
        tee >(sed 's/\x1b\[[0-9;]*m//g' >>"${logFile}")
    else
        cat
    fi
}

step_log_file() {
    local log_name="${HYDE_LOG:-manual}"
    printf '%s/logs/%s/install.steps.log\n' "${cacheDir}" "${log_name}"
}

run_step() {
    local label="$1"
    shift

    local log_file
    local start_time
    local end_time
    local exit_code
    log_file="$(step_log_file)"
    mkdir -p "$(dirname "${log_file}")"

    {
        printf '[%s] START %s ::' "$(date '+%Y-%m-%d %H:%M:%S')" "${label}"
        printf ' %q' "$@"
        printf '\n'
    } >>"${log_file}"
    print_log -sec "step" -stat "start" "${label}"

    start_time=$(date +%s)
    if "$@"; then exit_code=0; else exit_code=$?; fi
    end_time=$(date +%s)

    if [ "${exit_code}" -eq 0 ]; then
        printf '[%s] DONE  %s (%ss)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${label}" "$((end_time - start_time))" >>"${log_file}"
        print_log -sec "step" -stat "done" "${label} ($((end_time - start_time))s)"
    else
        printf '[%s] FAIL  %s (%ss, exit %s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${label}" "$((end_time - start_time))" "${exit_code}" >>"${log_file}"
        print_log -sec "step" -crit "failed" "${label} (exit ${exit_code})"
    fi

    return "${exit_code}"
}

if [ -r "${scrDir}/hardware/nvidia.sh" ]; then
    # shellcheck source=/dev/null
    source "${scrDir}/hardware/nvidia.sh"
fi
