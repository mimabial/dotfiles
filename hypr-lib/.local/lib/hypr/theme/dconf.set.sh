#!/usr/bin/env bash

# shellcheck disable=SC2154
# shellcheck disable=SC1091

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

# Stores default values for the theme to avoid breakages.
[[ -f "${HYPR_CONFIG_HOME}/env-theme" ]] && source "${HYPR_CONFIG_HOME}/env-theme"

dconf_populate() {
  # Build the dconf content
  cat <<EOF
[org/gnome/desktop/interface]
icon-theme='$ICON_THEME'
gtk-theme='$GTK_THEME'
color-scheme='$COLOR_SCHEME'
cursor-theme='$CURSOR_THEME'
cursor-size=$CURSOR_SIZE
font-name='$FONT $FONT_SIZE'
document-font-name='$DOCUMENT_FONT $DOCUMENT_FONT_SIZE'
monospace-font-name='$MONOSPACE_FONT $MONOSPACE_FONT_SIZE'
font-antialiasing='$FONT_ANTIALIASING'
font-hinting='$FONT_HINTING'

[org/gnome/desktop/default-applications/terminal]
exec='$(command -v "${TERMINAL}")'

[org/gnome/desktop/wm/preferences]
button-layout='$BUTTON_LAYOUT'
EOF
}

# HYPR_THEME="$(hyq "${HYPRLAND_CONFIG}" --source --query 'hypr:theme')"
COLOR_SCHEME="prefer-${dcol_mode}"

# Only use Pywal16-Gtk in wallpaper mode (enableWallDcol != 0)
# In theme mode (enableWallDcol == 0), use the theme's GTK_THEME
if [[ "${enableWallDcol:-1}" -ne 0 ]]; then
  GTK_THEME="Pywal16-Gtk"
else
  GTK_THEME=""  # Will be populated from theme.conf via hyq below
fi

# Populate variables from hyprland config if exists
if [[ -r "${HYPRLAND_CONFIG}" ]] &&
  command -v "hyq" &>/dev/null; then

  # In theme mode, prefer theme.conf for GTK/icon theme (avoid config.toml defaults overriding theme packs)
  if [[ "${enableWallDcol:-1}" -eq 0 ]]; then
    theme_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"
    if [[ -r "${theme_conf}" ]]; then
      eval "$(
        hyq "${theme_conf}" --export env --allow-missing \
          -Q '$GTK_THEME[string]' \
          -Q '$ICON_THEME[string]'
      )"
      GTK_THEME=${__GTK_THEME:-$GTK_THEME}
      ICON_THEME=${__ICON_THEME:-$ICON_THEME}
    fi
  fi

  hyq_args=(
    "${HYPRLAND_CONFIG}"
    --source
    --export env
    -Q '$COLOR_SCHEME[string]'
    -Q '$CURSOR_THEME[string]'
    -Q '$CURSOR_SIZE'
    -Q '$TERMINAL[string]'
    -Q '$FONT[string]'
    -Q '$FONT_SIZE'
    -Q '$DOCUMENT_FONT[string]'
    -Q '$DOCUMENT_FONT_SIZE'
    -Q '$MONOSPACE_FONT[string]'
    -Q '$MONOSPACE_FONT_SIZE'
    -Q '$BUTTON_LAYOUT[string]'
    -Q '$FONT_ANTIALIASING[string]'
    -Q '$FONT_HINTING[string]'
  )

  # Only pull GTK/icon theme from the full config in wallpaper mode.
  if [[ "${enableWallDcol:-1}" -ne 0 ]]; then
    hyq_args+=(
      -Q '$GTK_THEME[string]'
      -Q '$ICON_THEME[string]'
    )
  fi

  query_output=$(hyq "${hyq_args[@]}")
  eval "$query_output"
  GTK_THEME=${__GTK_THEME:-$GTK_THEME}
  COLOR_SCHEME=${__COLOR_SCHEME:-$COLOR_SCHEME}
  ICON_THEME=${__ICON_THEME:-$ICON_THEME}
  CURSOR_THEME=${__CURSOR_THEME:-$CURSOR_THEME}
  CURSOR_SIZE=${__CURSOR_SIZE:-$CURSOR_SIZE}
  TERMINAL=${__TERMINAL:-$TERMINAL}
  FONT=${__FONT:-$FONT}
  FONT_SIZE=${__FONT_SIZE:-$FONT_SIZE}
  DOCUMENT_FONT=${__DOCUMENT_FONT:-$DOCUMENT_FONT}
  DOCUMENT_FONT_SIZE=${__DOCUMENT_FONT_SIZE:-$DOCUMENT_FONT_SIZE}
  MONOSPACE_FONT=${__MONOSPACE_FONT:-$MONOSPACE_FONT}
  MONOSPACE_FONT_SIZE=${__MONOSPACE_FONT_SIZE:-$MONOSPACE_FONT_SIZE}
  BUTTON_LAYOUT=${__BUTTON_LAYOUT:-$BUTTON_LAYOUT}
  FONT_ANTIALIASING=${__FONT_ANTIALIASING:-$FONT_ANTIALIASING}
  FONT_HINTING=${__FONT_HINTING:-$FONT_HINTING}
fi

# Check if we need inverted colors
if [[ "${revert_colors:-0}" -eq 1 ]] ||
  [[ "${enableWallDcol:-0}" -eq 2 && "${dcol_mode:-}" == "light" ]] ||
  [[ "${enableWallDcol:-0}" -eq 3 && "${dcol_mode:-}" == "dark" ]]; then
  if [[ "${dcol_mode}" == "dark" ]]; then
    COLOR_SCHEME="prefer-light"
  else
    COLOR_SCHEME="prefer-dark"
  fi
fi

DCONF_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/dconf"
mkdir -p "$(dirname "${DCONF_FILE}")"

# Generate new dconf content
new_content="$(dconf_populate)"

# Hash-based skip: only update if content changed
old_hash=""
new_hash="$(echo "${new_content}" | md5sum | cut -d' ' -f1)"
[ -f "${DCONF_FILE}" ] && old_hash="$(md5sum "${DCONF_FILE}" 2>/dev/null | cut -d' ' -f1)"

if [ "${new_hash}" != "${old_hash}" ]; then
  echo "${new_content}" > "${DCONF_FILE}"
  # Single dconf load is all that's needed
  if dconf load -f / < "${DCONF_FILE}"; then
    print_log -sec "dconf" -stat "loaded" "${DCONF_FILE}"
  else
    print_log -sec "dconf" -warn "failed" "${DCONF_FILE}"
  fi
else
  print_log -sec "dconf" -stat "skip" "unchanged"
fi

# Set cursor (run in background, non-blocking)
[[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]] && hyprctl setcursor "${CURSOR_THEME}" "${CURSOR_SIZE}" &

print_log -sec "dconf" -stat "Loaded dconf settings" "::"
print_log -y "#-----------------------------------------------#"
dconf_populate
print_log -y "#-----------------------------------------------#"

# Finalize the env variables
export GTK_THEME ICON_THEME COLOR_SCHEME CURSOR_THEME CURSOR_SIZE TERMINAL \
  FONT FONT_SIZE DOCUMENT_FONT DOCUMENT_FONT_SIZE MONOSPACE_FONT MONOSPACE_FONT_SIZE \
  BAR_FONT MENU_FONT NOTIFICATION_FONT BUTTON_LAYOUT
