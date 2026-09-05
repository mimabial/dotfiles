#compdef tds

_tds_completion() {
    (( CURRENT == 2 )) || return 0

    _tdl_completion_agent_names
    compadd -Q -a reply
    _command_names -e
}

compdef _tds_completion tds
