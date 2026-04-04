#compdef tdl

_tdl_completion_agent_names() {
    local key
    local -a agent_names

    if (( ${+_TDL_AGENT_BEHAVIOR_FLAGS} )); then
        for key in "${(@k)_TDL_AGENT_BEHAVIOR_FLAGS}"; do
            agent_names+=("${key%%:*}")
        done
    fi

    agent_names+=(claude codex)
    reply=("${(@ou)agent_names}")
}

_tdl_completion() {
    local arg positional_count=0
    integer dual_mode=0 parsing_options=1

    _arguments -C \
        '--git[open a git side window]' \
        '--docker[open a docker side window]' \
        '(-d --dual)'{-d,--dual}'[open two-agent layout]' \
        '*::tdl argument:->args' || return 0

    [[ "$state" == args ]] || return 0

    for arg in "${words[@]:1:$((CURRENT - 2))}"; do
        if (( parsing_options )); then
            case "$arg" in
                --dual | -d)
                    dual_mode=1
                    continue
                    ;;
                --git | --docker)
                    continue
                    ;;
                --)
                    parsing_options=0
                    continue
                    ;;
                -*)
                    continue
                    ;;
            esac
        fi

        ((positional_count++))
    done

    (( positional_count == 0 )) || {
        (( positional_count == 1 && dual_mode )) || return 0
    }

    _tdl_completion_agent_names
    compadd -Q -a reply
    _command_names -e
}

compdef _tdl_completion tdl
