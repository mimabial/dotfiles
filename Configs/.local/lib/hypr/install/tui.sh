#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell install/tui [name exec float|tile icon-url]
Create a TUI app-launcher desktop entry (prompts when args are omitted)." "$@"

desktop_exec_escape() {
  local value="$1"

  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\$/\\\$}
  value=${value//\`/\\\`}

  printf '%s\n' "$value"
}

if [ "$#" -ne 4 ]; then
  echo -e "\e[32mLet's create a TUI shortcut you can start with the app launcher.\n\e[0m"
  read -r -p "Name> " APP_NAME
  [[ -z "$APP_NAME" ]] && exit 0
  read -r -p "Launch Command> " APP_EXEC
  [[ -z "$APP_EXEC" ]] && exit 0
  WINDOW_STYLE=$(echo -e "float\ntile" | fzf --prompt="Window style > " --height=3 --reverse)
  [[ -z "$WINDOW_STYLE" ]] && exit 0
  read -r -p "Icon URL> " ICON_URL
  [[ -z "$ICON_URL" ]] && exit 0
else
  APP_NAME="$1"
  APP_EXEC="$2"
  WINDOW_STYLE="$3"
  ICON_URL="$4"
fi

if [[ -z "$APP_NAME" || -z "$APP_EXEC" || -z "$ICON_URL" ]]; then
  echo "You must set app name, app command, and icon URL!"
  exit 1
fi

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
ICON_DIR="${XDG_DATA_HOME}/applications/icons"
DESKTOP_FILE="${XDG_DATA_HOME}/applications/$APP_NAME.desktop"

if [[ ! "$ICON_URL" =~ ^https?:// ]] && [ -f "$ICON_URL" ]; then
  ICON_PATH="$ICON_URL"
else
  ICON_PATH="$ICON_DIR/$APP_NAME.png"
  mkdir -p "$ICON_DIR"
  if ! curl -sL -o "$ICON_PATH" "$ICON_URL"; then
    echo "Error: Failed to download icon."
    exit 1
  fi
fi

if [[ $WINDOW_STYLE == "float" ]]; then
  APP_CLASS="org.tui.Terminal"
  EXEC_PREFIX="tui-terminal-exec --hypr-profile tui --app-id=$APP_CLASS -- "
else
  APP_CLASS="TUI.tile"
  EXEC_PREFIX="tui-terminal-exec --app-id=$APP_CLASS -- "
fi

APP_EXEC_DESKTOP=$(desktop_exec_escape "$APP_EXEC")

cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=$APP_NAME
Comment=$APP_NAME
Exec=${EXEC_PREFIX}bash -lc "$APP_EXEC_DESKTOP"
Terminal=false
Type=Application
Icon=$ICON_PATH
StartupNotify=true
X-Hypr-Tui=true
EOF

chmod +x "$DESKTOP_FILE"

if [ "$#" -ne 4 ]; then
  echo -e "You can now find $APP_NAME using the app launcher (SUPER + SPACE)\n"
fi
