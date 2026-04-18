#compdef hyprshell

_hyprshell() {
    local cur prev words
    cur="${words[CURRENT]}"
    prev="${words[CURRENT-1]}"

    local built_in_commands hyprscripts
    built_in_commands=("--help" "help" "-h" "-r" "reload" "--version" "version" "-v" "--release-notes" "release-notes" "--list-script" "--list-script-path" "--completions" "validate" "pyinit" "init" "lock-session" "logout" "pip" "pypr" "app" )

    if (( $+commands[hyprshell] )); then
        local scripts_raw
        scripts_raw=(${(f)"$(hyprshell --list-script 2>/dev/null)"})
        hyprscripts=(${scripts_raw[@]%.*})
    fi

    if [[ $CURRENT -eq 2 ]]; then
        local all_commands=($built_in_commands $hyprscripts)
        compadd -M 'r:|/=* r:|=*' -a all_commands
    elif [[ $CURRENT -eq 3 ]]; then
        case $words[2] in
            --completions)
                compadd "bash" "zsh"
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    else
        return 0
    fi
}

compdef _hyprshell hyprshell
