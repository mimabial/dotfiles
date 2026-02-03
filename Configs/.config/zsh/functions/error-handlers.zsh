function command_not_found_handler {
    emulate -L zsh
    setopt localoptions extendedglob
    local purple='\e[1;35m' bright='\e[0;1m' green='\e[1;32m' reset='\e[0m'

    if (( ! ${+PM_COMMAND} )) || (( ${#PM_COMMAND} == 0 )) || ! command -v "${PM_COMMAND[1]}" >/dev/null 2>&1; then
        printf "${green}zsh${reset}: command ${purple}NOT${reset} found: ${bright}'%s'${reset}\n" "$1"
        return 127
    fi

    printf "${green}zsh${reset}: command ${purple}NOT${reset} found: ${bright}'%s'${reset}\n" "$1"

    if [[ "${ZSH_CNF_SEARCH:-1}" != "1" ]]; then
        return 127
    fi

    printf "${bright}Searching for packages that provide '${bright}%s${green}'...\n${reset}" "${1}"

    local output exit_code
    output=$("${PM_COMMAND[@]}" fq "/usr/bin/$1" 2>&1)
    exit_code=$?

    local -a lines filtered
    lines=("${(@f)output}")
    for line in "${lines[@]}"; do
        [[ -z "$line" ]] && continue
        local cleaned="${line//$'\r'/}"
        cleaned="${cleaned//$'\e'\[[0-9;]##[[:alpha:]]/}"
        cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"
        cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
        [[ -z "$cleaned" ]] && continue
        [[ "$cleaned" == "-> exit status "* ]] && continue
        filtered+=("$line")
    done
    output="${(F)filtered}"

    if (( exit_code != 0 )); then
        if [[ -z "$output" ]]; then
            printf "${bright}(no package provides it)${reset}\n"
        else
            printf "${bright}Package query failed:${reset}\n"
            printf "%s\n" "$output"
        fi
        return 127
    fi

    if [[ -z "$output" ]]; then
        printf "${bright}(no package provides it)${reset}\n"
        return 127
    fi

    printf "${green}Packages that might provide it:${reset}\n"
    printf "%s\n" "$output"
    return 127
}

# Function to display a slow load warning
# the intention is for hyprdots users who might have multiple zsh initialization
function _slow_load_warning {
    local lock_file="/tmp/.slow_load_warning.lock"
    local load_time=$SECONDS

    # Check if the lock file exists
    if [[ ! -f $lock_file ]]; then
        # Create the lock file
        touch $lock_file

        # Display the warning if load time exceeds the limit
        time_limit=3
        if ((load_time > time_limit)); then
            cat <<EOF
    ⚠️ Warning: Shell startup took more than ${time_limit} seconds. Consider optimizing your configuration.
        1. This might be due to slow plugins, slow initialization scripts.
        2. Duplicate plugins initialization.
        3. Slow initialization scripts.

EOF
        fi
    fi
}

# Function to handle initialization errors
function handle_init_error {
    if [[ $? -ne 0 ]]; then
        echo "Error during initialization. Please check your configuration."
    fi
}

function no_such_file_or_directory_handler {
    local red='\e[1;31m' reset='\e[0m'
    printf "${red}zsh: no such file or directory: %s${reset}\n" "$1"
    return 127
}
