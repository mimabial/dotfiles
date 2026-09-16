#!/bin/sh
# Foreground tmux server for a supervisor (systemd unit or runit run script).
# `tmux -D` keeps the server in the foreground so the supervisor signals it
# directly and no kill-server is needed on stop, but it forbids a command, so
# the default session comes from the startup config instead.

case "${1:-}" in
-h | --help)
	printf 'Usage: hyprshell system/tmux-server\nRun the tmux server in the foreground and ensure a default session exists.\n'
	exit 0
	;;
esac

# `tmux -D` cannot start a second server, so a server started outside the
# supervisor is adopted instead: wait-for needs no terminal and returns when
# that server dies, which keeps the supervisor tracking the real lifetime.
if tmux has-session 2>/dev/null; then
	exec tmux wait-for tmux-server-supervised
fi

exec tmux -D -f /dev/stdin <<EOF
source-file -q /etc/tmux.conf ~/.tmux.conf "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
new-session -d
EOF
