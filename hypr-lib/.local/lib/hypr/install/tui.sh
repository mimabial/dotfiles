#!/bin/bash

if [ "$#" -ne 4 ]; then
  echo -e "\e[32mLet's create a TUI shortcut you can start with the app launcher.\n\e[0m"
  read -p "Name> " APP_NAME
  [[ -z "$APP_NAME" ]] && exit 0
  read -p "Launch Command> " APP_EXEC
  [[ -z "$APP_EXEC" ]] && exit 0
  WINDOW_STYLE=$(echo -e "float\ntile" | fzf --prompt="Window style > " --height=3 --reverse)
  [[ -z "$WINDOW_STYLE" ]] && exit 0
  read -p "Icon URL> " ICON_URL
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

ICON_DIR="$HOME/.local/share/applications/icons"
DESKTOP_FILE="$HOME/.local/share/applications/$APP_NAME.desktop"

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
  APP_CLASS="TUI.float"
else
  APP_CLASS="TUI.tile"
fi

cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=$APP_NAME
Comment=$APP_NAME
Exec=\$TERMINAL_TUI --class=$APP_CLASS -e $APP_EXEC
Terminal=false
Type=Application
Icon=$ICON_PATH
StartupNotify=true
EOF

chmod +x "$DESKTOP_FILE"

if [ "$#" -ne 4 ]; then
  echo -e "You can now find $APP_NAME using the app launcher (SUPER + SPACE)\n"
fi
