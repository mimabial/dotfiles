#compdef denv-shell

_denv_shell() {
    local cur prev words
    cur="${words[CURRENT]}"
    prev="${words[CURRENT-1]}"
    
    local built_in_commands denv_scripts wallbash_scripts
    built_in_commands=("--help" "help" "-h" "-r" "reload" "wallbash" "--version" "version" "-v" "--release-notes" "release-notes" "--list-script" "--list-script-path" "--completions")
    
    # Get dynamic completions
    if (( $+commands[denv-shell] )); then
        local scripts_raw
        scripts_raw=(${(f)"$(denv-shell --list-script 2>/dev/null)"})
        denv_scripts=(${scripts_raw[@]%.*})  # Remove extensions
        
        # Get wallbash scripts - just --help for now
        wallbash_scripts=("--help")
    fi
    
    # Only complete for first two arguments max
    if [[ $CURRENT -eq 2 ]]; then
        # First argument: all commands
        local all_commands=($built_in_commands $denv_scripts)
        compadd -a all_commands
    elif [[ $CURRENT -eq 3 ]]; then
        # Second argument: only for specific commands
        case $words[2] in
            wallbash)
                compadd -a wallbash_scripts
                return 0
                ;;
            --completions)
                compadd "bash" "zsh" "fish"
                return 0
                ;;
            *)
                # No completion for other commands
                return 0
                ;;
        esac
    else
        # No completion for 3rd argument and beyond
        return 0
    fi
}

compdef _denv_shell denv-shell
