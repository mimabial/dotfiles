#compdef agent-notify

_agent_notify_pending_ids() {
    local -a pending_ids

    if command -v agent-notify >/dev/null 2>&1; then
        pending_ids=(${(f)"$(AGENT_NOTIFY_DISABLE_DESKTOP=1 agent-notify pending 2>/dev/null | awk -F' \\| ' 'NF { print $1 }')"})
    fi

    reply=("${pending_ids[@]}")
}

_agent_notify() {
    local curcontext="$curcontext" state line

    _arguments -C \
        '1:command:(send ask answer pending help)' \
        '*::argument:->args' || return 0

    case "${words[2]:-}" in
        send|ask)
            _arguments \
                '(-t --title)'{-t,--title}'[notification title]:title:' \
                '(-m --message)'{-m,--message}'[notification message]:message:' \
                '(-u --urgency)'{-u,--urgency}'[urgency level]:(low normal high critical)' \
                '(-s --source)'{-s,--source}'[source prefix override]:source:' \
                '(-S --no-source)'{-S,--no-source}'[disable source prefix]' \
                '(-q --question)'{-q,--question}'[track as a pending question]' \
                '(-h --help)'{-h,--help}'[show help]'
            ;;
        answer)
            if [[ "${words[CURRENT-1]:-}" == "-i" || "${words[CURRENT-1]:-}" == "--id" ]]; then
                _agent_notify_pending_ids
                compadd -a reply
                return 0
            fi

            _arguments \
                '(-i --id)'{-i,--id}'[pending question ID]:pending id:' \
                '(-t --title)'{-t,--title}'[pending question title]:title:' \
                '(-m --message)'{-m,--message}'[pending question message]:message:' \
                '(-s --source)'{-s,--source}'[source filter]:source:' \
                '(-h --help)'{-h,--help}'[show help]'
            ;;
        pending|help)
            return 0
            ;;
    esac
}

compdef _agent_notify agent-notify
