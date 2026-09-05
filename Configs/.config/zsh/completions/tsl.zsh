#compdef tsl

_tsl_completion() {
    (( CURRENT >= 2 && CURRENT <= 5 )) || return 0

    _tdl_completion_agent_names
    compadd -Q -a reply
    _command_names -e
}

compdef _tsl_completion tsl
