#!/usr/bin/env bash

nvidia_detect() {
    local mode="${1:-}"
    local -a gpus=()
    local -a driver_db=()
    local nvcode

    if ! command -v lspci >/dev/null 2>&1; then
        [ "${mode}" = "--verbose" ] && echo "lspci not found; unable to inspect GPUs"
        return 1
    fi

    readarray -t gpus < <(lspci -k | awk '/^[[:xdigit:]:.]+ .*((VGA compatible controller)|(3D controller))/ {sub(/^[^ ]+ /, ""); print}')

    case "${mode}" in
    --verbose)
        if [ "${#gpus[@]}" -eq 0 ]; then
            echo "No VGA/3D GPU entries detected"
            return 0
        fi
        for indx in "${!gpus[@]}"; do
            echo -e "\033[0;32m[gpu$indx]\033[0m detected :: ${gpus[indx]}"
        done
        return 0
        ;;
    --drivers)
        driver_db=("${scrDir}"/nvidia-db/nvidia*dkms)
        [ -e "${driver_db[0]}" ] || return 0
        while IFS= read -r -d ' ' nvcode; do
            [ -n "${nvcode}" ] || continue
            awk -F '|' -v nvc="${nvcode}" 'substr(nvc,1,length($3)) == $3 {split(FILENAME,driver,"/"); print driver[length(driver)],"\nnvidia-utils"}' "${driver_db[@]}"
        done < <(printf '%s ' "${gpus[@]}") | sort -u
        return 0
        ;;
    esac

    grep -iq nvidia <<<"${gpus[*]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    scrDir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
    nvidia_detect "${1:---verbose}"
fi
