#!/usr/bin/env bash

# Returns the best working directory for terminal-launch keybinds.
# Prefers Kitty's reported cwd for the focused Kitty window, then falls back
# to the active terminal's child shell cwd, then finally $HOME.

active_window_json="$(hyprctl activewindow -j 2>/dev/null || true)"
active_class="$(printf '%s' "${active_window_json}" | jq -r '.class // empty' 2>/dev/null || true)"
terminal_pid="$(printf '%s' "${active_window_json}" | jq -r '.pid // empty' 2>/dev/null || true)"
shell_pid=""
cwd=""
shell_path=""
kitty_cwd=""

if [[ "${active_class}" == "kitty" ]] && command -v kitty >/dev/null 2>&1; then
  kitty_cwd="$(
    kitty @ ls 2>/dev/null \
      | jq -r '
          first(
            .. | objects
            | select(.is_active? == true and .is_focused? == true and (.cwd? | type == "string"))
            | .cwd
            | select(length > 0)
          )
        ' 2>/dev/null || true
  )"
  if [[ -d "${kitty_cwd}" ]]; then
    printf '%s\n' "${kitty_cwd}"
    exit 0
  fi
fi

[[ "${terminal_pid}" =~ ^[0-9]+$ ]] || {
  printf '%s\n' "${HOME}"
  exit 0
}

shell_pid="$(pgrep -P "${terminal_pid}" | tail -n1)"

if [[ -n "${shell_pid}" ]]; then
  cwd="$(readlink -f "/proc/${shell_pid}/cwd" 2>/dev/null || true)"
  shell_path="$(readlink -f "/proc/${shell_pid}/exe" 2>/dev/null || true)"

  if [[ -d "${cwd}" ]] && grep -qs "${shell_path}" /etc/shells; then
    printf '%s\n' "${cwd}"
    exit 0
  fi
fi

printf '%s\n' "${HOME}"
