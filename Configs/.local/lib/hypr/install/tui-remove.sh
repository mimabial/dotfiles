#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell install/tui-remove [name...]
Remove TUI desktop entries (fzf multi-select when none given)." "$@"

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
ICON_DIR="${XDG_DATA_HOME}/applications/icons"
DESKTOP_DIR="${XDG_DATA_HOME}/applications/"

if [ "$#" -eq 0 ]; then
  # Find all TUIs
  while IFS= read -r -d '' file; do
    if grep -Eq '^X-Hypr-Tui=true$' "$file" || grep -Eq '^Exec=(\$TERMINAL_TUI|tui-terminal-exec)\b' "$file"; then
      TUIS+=("$(basename "${file%.desktop}")")
    fi
  done < <(find "$DESKTOP_DIR" -name '*.desktop' -print0)

  if ((${#TUIS[@]})); then
    mapfile -t SORTED_TUIS < <(printf '%s\n' "${TUIS[@]}" | sort)
    APP_NAMES_STRING=$(printf '%s\n' "${SORTED_TUIS[@]}" | fzf --multi --prompt="Select TUIs to remove (TAB to select) > " --header="Select one or more TUIs" --reverse)
    # Convert newline-separated string to array
    APP_NAMES=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && APP_NAMES+=("$line")
    done <<< "$APP_NAMES_STRING"
  else
    echo "No TUIs to remove."
    exit 1
  fi
else
  # Use array to preserve spaces in app names
  APP_NAMES=("$@")
fi

if [[ ${#APP_NAMES[@]} -eq 0 ]]; then
  echo "You must provide TUI names."
  exit 1
fi

for APP_NAME in "${APP_NAMES[@]}"; do
  rm -f "$DESKTOP_DIR/$APP_NAME.desktop"
  rm -f "$ICON_DIR/$APP_NAME.png"
  echo "Removed $APP_NAME"
done
