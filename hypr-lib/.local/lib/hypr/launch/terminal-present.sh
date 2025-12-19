#!/bin/bash

cmd="$*"

# Interactive programs that don't need "Done! Press any key" prompt
interactive_programs="ranger|nvim|vim|htop|btop|bottom|nano|less|more|rmpc"

if [[ "$cmd" =~ ^($interactive_programs)($|[[:space:]]) ]]; then
  exec setsid uwsm-app -- tui-terminal-exec --app-id=org.tui.Terminal --title=Terminal -e bash -c "clear; $cmd"
else
  exec setsid uwsm-app -- tui-terminal-exec --app-id=org.tui.Terminal --title=Terminal -e bash -c "clear; $cmd; echo; echo 'Done. Press any key to close.'; read -r -n 1 _ </dev/tty"
fi
