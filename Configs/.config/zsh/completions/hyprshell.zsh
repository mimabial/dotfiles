#compdef hyprshell

_hyprshell() {
    # Never declare `words` local: it is the completion system's array, and
    # shadowing it leaves $words[2] empty so the subcommand cannot be read.
    local built_in_commands hyprscripts
    built_in_commands=("--help" "help" "-h" "-r" "reload" "--version" "version" "-v" "--release-notes" "release-notes" "list" "--list-script" "--list-script-path" "--completions" "validate" "pyinit" "init" "lock-session" "logout" "pip" "pypr" "app" )

    if (( $+commands[hyprshell] )); then
        hyprscripts=(${(f)"$(hyprshell --list-script 2>/dev/null)"})
    fi

    if [[ $CURRENT -eq 2 ]]; then
        local all_commands=($built_in_commands $hyprscripts)
        compadd -M 'r:|/=* r:|=*' -a all_commands
    elif [[ $CURRENT -eq 3 && $words[2] == --completions ]]; then
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
    local name="$1" cache line
    local -a entry mt sz
    [[ -n "$name" ]] || return 0
    cache="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/completion-options"
    zmodload -F zsh/stat b:zstat 2>/dev/null

    if [[ -r "$cache" ]]; then
        for line in ${(f)"$(<$cache)"}; do
            [[ $line == $name$'\t'* ]] || continue
            # (ps:...:) not (s:...:) — the latter splits on a literal backslash-t.
            entry=(${(ps:\t:)line})
            zstat -A mt +mtime $entry[2] 2>/dev/null
            zstat -A sz +size $entry[2] 2>/dev/null
            if [[ $mt[1] == $entry[3] && $sz[1] == $entry[4] ]]; then
                print -r -- $entry[5]
                return 0
            fi
            break
        done
    fi

    local helper="${LIB_DIR:-$HOME/.local/lib}/hypr/shell/lib/hyprshell.options.py"
    [[ -r $helper ]] && python3 $helper $name 2>/dev/null
}

compdef _hyprshell hyprshell
