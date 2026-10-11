#compdef hyprshell

_hyprshell() {
    # Never declare `words` local: it is the completion system's array, and
    # shadowing it leaves $words[2] empty so the subcommand cannot be read.
    local -a builtin_commands script_commands
    builtin_commands=("--help" "help" "-h" "-r" "reload" "--version" "version" "-v" "--release-notes" "release-notes" "list" "--list-script" "--list-script-path" "--completions" "completions" "pyinit" "init" "--init" "logout" "pip" "app" "resolve" )

    if [[ $CURRENT -eq 2 ]]; then
        if (( $+commands[hyprshell] )); then
            script_commands=(${(f)"$(hyprshell --list-script 2>/dev/null)"})
        fi
        local all_commands=($builtin_commands $script_commands)
        compadd -M 'r:|/=* r:|=*' -a all_commands
    elif [[ $CURRENT -eq 3 && ($words[2] == --completions || $words[2] == completions) ]]; then
        compadd "bash" "zsh"
    else
        local -a script_options
        script_options=(${=$(_hyprshell_script_options $words[2])})
        if (( ${#script_options} )); then
            # Two tagged groups, so options and paths are offered side by side.
            _alternative \
                "options:script option:compadd -a script_options" \
                "files:file:_files"
        else
            _files
        fi
    fi
}

# Cache hit stays inside zsh: no subprocess, no interpreter start. Python runs
# only when the script changed, and then reparses just that one file.
_hyprshell_script_options() {
    local command_name="$1" cache_file cache_line
    local cached_name script_path modified_seconds size_bytes cached_options
    local -A script_stat
    [[ -n "$command_name" ]] || return 0
    cache_file="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/completion-options"
    zmodload -F zsh/stat b:zstat 2>/dev/null

    if [[ -r "$cache_file" ]]; then
        for cache_line in ${(f)"$(<$cache_file)"}; do
            [[ $cache_line == $command_name$'\t'* ]] || continue
            IFS=$'\t' read -r cached_name script_path modified_seconds size_bytes cached_options <<<"$cache_line"
            if zstat -H script_stat "$script_path" 2>/dev/null &&
                [[ $script_stat[mtime] == $modified_seconds && $script_stat[size] == $size_bytes ]]; then
                print -r -- "$cached_options"
                return 0
            fi
            break
        done
    fi

    local helper="${LIB_DIR:-$HOME/.local/lib}/hypr/shell/lib/hyprshell.completion-options.py"
    [[ -r $helper ]] && python3 "$helper" "$command_name" 2>/dev/null
}

compdef _hyprshell hyprshell
