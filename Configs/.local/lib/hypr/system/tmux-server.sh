#!/bin/sh
# Foreground tmux server for a supervisor (systemd unit or runit run script).
# `tmux -D` keeps the server in the foreground so the supervisor signals it
# directly and no kill-server is needed on stop, but it forbids a command, so
# the default session is created by a helper once the socket is up.

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

(
	i=0
	while [ "$i" -lt 50 ]; do
		tmux has-session 2>/dev/null && exit 0
		tmux new-session -d 2>/dev/null && exit 0
		i=$((i + 1))
		sleep 0.1
	done
) &

exec tmux -D
