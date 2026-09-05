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
    (( CURRENT >= 2 && CURRENT <= 3 )) || return 0

    _tdl_completion_agent_names
    compadd -Q -a reply
    _command_names -e
}

compdef _tdl_completion tdl
