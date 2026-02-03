#!/usr/bin/env bash
# wal.kitty.sh - Reload kitty config after theme updates (ensures font changes apply)

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

KITTY_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
KITTY_THEME_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/theme.conf"

if ! pgrep -x kitty >/dev/null 2>&1; then
  exit 0
fi

if [[ ! -f "${KITTY_THEME_CONF}" ]]; then
  pkill -SIGUSR1 kitty 2>/dev/null || true
  exit 0
fi

if ! grep -Eq '^[[:space:]]*(font_family|bold_font|italic_font|bold_italic_font|font_size|modify_font)[[:space:]]+' "${KITTY_THEME_CONF}"; then
  pkill -SIGUSR1 kitty 2>/dev/null || true
  exit 0
fi

listen_on="${KITTY_LISTEN_ON:-}"
if [[ -z "${listen_on}" ]] && [[ -f "${KITTY_CONF}" ]]; then
  listen_on="$(awk '
    /^[[:space:]]*#/ {next}
    $1 == "listen_on" {print $2; exit}
  ' "${KITTY_CONF}")"
fi
listen_on="${listen_on:-unix:/tmp/kitty}"

if command -v kitten >/dev/null 2>&1; then
  if [[ "${listen_on}" == unix:* ]]; then
    socket_path="${listen_on#unix:}"
    if [[ "${socket_path}" == @* ]] || [[ -S "${socket_path}" ]]; then
      if kitten @ --to "${listen_on}" load-config >/dev/null 2>&1; then
        exit 0
      fi
    fi
  else
    if kitten @ --to "${listen_on}" load-config >/dev/null 2>&1; then
      exit 0
    fi
  fi
fi

pkill -SIGUSR1 kitty 2>/dev/null || true
