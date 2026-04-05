#!/usr/bin/env bash

search_root="$(hyprshell terminal-cwd.sh)"
[[ -d "${search_root}" ]] || search_root="${HOME}"

FILE_FINDER_ROOT="${search_root}" \
  exec hyprshell launch/tui.sh \
    --app-id org.tui.FileFinder \
    --title "File Finder" \
    -- zsh -lc '
      source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/functions/fzf.zsh"
      _fuzzy_edit_search_file --root "${FILE_FINDER_ROOT:-$HOME}"
    '
