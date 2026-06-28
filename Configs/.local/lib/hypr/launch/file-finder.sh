#!/usr/bin/env bash
#
# file-finder.sh — Open the fzf fuzzy-edit file finder rooted at the focused terminal's CWD (falling back to $HOME).
#
# Usage: file-finder.sh
#
# Depends on: hyprshell terminal-cwd.sh, hyprshell launch/tui.sh, zsh, ${XDG_CONFIG_HOME}/zsh/functions/fzf.zsh
#
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell launch/file-finder
Open the fzf fuzzy-edit file finder at the focused terminal's CWD (falls back to \$HOME)." "$@"

search_root="$(hyprshell terminal-cwd.sh)"
[[ -d "${search_root}" ]] || search_root="${HOME}"

# shellcheck disable=SC2016 # The inner zsh expands FILE_FINDER_ROOT.
FILE_FINDER_ROOT="${search_root}" \
  exec hyprshell launch/tui.sh \
    --app-id org.tui.FileFinder \
    --title "File Finder" \
    -- zsh -lc '
      source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/functions/fzf.zsh"
      _fuzzy_edit_search_file --root "${FILE_FINDER_ROOT:-$HOME}"
    '
