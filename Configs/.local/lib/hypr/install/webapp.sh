#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/install/lib/desktop-entry.bash"
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell install/webapp [name url icon-url [exec] [mime]]
Create a web-app launcher and desktop entry (prompts when args are omitted)." "$@"

prompt_required_value() {
  local prompt="$1"
  local value=""
  read -r -p "${prompt}> " value
  [[ -n "${value}" ]] || return 1
  printf '%s\n' "${value}"
}

download_or_resolve_icon_path() {
  local icon_ref="$1"
  local app_id="$2"
  mkdir -p "$DESKTOP_ENTRY_ICON_DIR"
  case "$icon_ref" in
    http://* | https://*)
      local icon_path="${DESKTOP_ENTRY_ICON_DIR}/${app_id}.png"
      curl -fsSL -o "$icon_path" "$icon_ref" || {
        echo "Error: Failed to download icon."
        return 1
      }
      printf '%s\n' "$icon_path"
      ;;
    *)
      [[ -f "$icon_ref" ]] && printf '%s\n' "$icon_ref" || printf '%s\n' "${DESKTOP_ENTRY_ICON_DIR}/${icon_ref}"
      ;;
  esac
}

build_webapp_launcher_argv() {
  local -n launcher_argv_ref="$1"
  local app_url="$2" custom_exec="$3"

  if [[ -z "${custom_exec}" ]]; then
    launcher_argv_ref=(hyprshell launch/webapp.sh "${app_url}")
    return 0
  fi
  desktop_entry_exec_tokenize_spec "${custom_exec}" || return 1
  launcher_argv_ref=("${DESKTOP_ENTRY_ARGV[@]}")
}

if [[ "$#" -lt 3 ]]; then
  echo -e "\e[32mLet's create a new web app you can start with the app launcher.\n\e[0m"
  APP_NAME="$(prompt_required_value "Name")" || exit 0
  APP_URL="$(prompt_required_value "URL")" || exit 0
  ICON_REF="$(prompt_required_value "Icon URL")" || exit 0
  CUSTOM_EXEC=""
  MIME_TYPES=""
  INTERACTIVE_MODE=true
else
  APP_NAME="${1:-}"
  APP_URL="${2:-}"
  ICON_REF="${3:-}"
  CUSTOM_EXEC="${4-}"
  MIME_TYPES="${5-}"
  INTERACTIVE_MODE=false
fi

if [[ -z "$APP_NAME" || -z "$APP_URL" || -z "$ICON_REF" ]]; then
  echo "You must set app name, app URL, and icon URL!"
  exit 1
fi

APP_ID="$(desktop_entry_safe_id "$APP_NAME")"
DESKTOP_FILE="${DESKTOP_ENTRY_DIR}/${APP_ID}.desktop"
LAUNCHER_PATH="${WEBAPP_LAUNCHER_DIR}/${APP_ID}"
ICON_PATH="$(download_or_resolve_icon_path "$ICON_REF" "$APP_ID")" || exit 1

launcher_argv=()
build_webapp_launcher_argv launcher_argv "$APP_URL" "$CUSTOM_EXEC" || exit 1
desktop_entry_write_exec_launcher "$LAUNCHER_PATH" "${launcher_argv[@]}"
desktop_entry_normalize_mime_types MIME_TYPES_DESKTOP "$MIME_TYPES" || exit 1

mkdir -p "$DESKTOP_ENTRY_DIR"

APP_NAME_DESKTOP="$(desktop_entry_escape_string_value "$APP_NAME")"
COMMENT_DESKTOP="$(desktop_entry_escape_string_value "$APP_NAME")"
ICON_PATH_DESKTOP="$(desktop_entry_escape_string_value "$ICON_PATH")"
LAUNCHER_EXEC_DESKTOP="$(desktop_entry_quote_exec_arg "$LAUNCHER_PATH")"
APP_ID_DESKTOP="$(desktop_entry_escape_string_value "$APP_ID")"

cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME_DESKTOP
Comment=$COMMENT_DESKTOP
Exec=$LAUNCHER_EXEC_DESKTOP
Terminal=false
Icon=$ICON_PATH_DESKTOP
StartupNotify=true
$WEBAPP_MARKER
$WEBAPP_ID_KEY=$APP_ID_DESKTOP
EOF

if [[ -n "$MIME_TYPES_DESKTOP" ]]; then
  printf 'MimeType=%s\n' "$MIME_TYPES_DESKTOP" >>"$DESKTOP_FILE"
fi

chmod +x "$DESKTOP_FILE"

if [[ "$INTERACTIVE_MODE" == true ]]; then
  echo -e "You can now find $APP_NAME using the app launcher (SUPER + SPACE)\n"
fi
