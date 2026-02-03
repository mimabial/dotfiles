#!/bin/bash

app_id="org.tui.Terminal"
title="Terminal"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --app-id)
      app_id="$2"
      shift 2
      ;;
    --title)
      title="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

cmd="$*"
if [[ -z "$cmd" ]]; then
  echo "Usage: $(basename "$0") [--app-id ID] [--title TITLE] -- <command>"
  exit 1
fi

# Interactive programs that don't need "Done! Press any key" prompt
interactive_programs="ranger|nvim|vim|htop|btop|bottom|nano|less|more|rmpc|nvtop|dua|wiremix|bluetui|oryx"

if [[ "$cmd" =~ ^(sudo[[:space:]]+)?($interactive_programs)($|[[:space:]]) ]]; then
  exec setsid uwsm-app -- tui-terminal-exec --app-id="$app_id" --title="$title" -e bash -c "clear; $cmd"
else
  exec setsid uwsm-app -- tui-terminal-exec --app-id="$app_id" --title="$title" -e bash -c "clear; $cmd; echo; echo 'Done. Press any key to close.'; read -r -n 1 _ </dev/tty"
fi
