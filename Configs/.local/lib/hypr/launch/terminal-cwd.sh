#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell launch/terminal-cwd
Print the best working directory for terminal-launch keybinds." "$@"

active_window_json="$(hyprctl activewindow -j 2>/dev/null || true)"
active_class=""
active_title=""
terminal_pid=""
[[ "${active_window_json}" =~ \"class\":\ \"([^\"]*)\" ]] && active_class="${BASH_REMATCH[1]}"
[[ "${active_window_json}" =~ \"title\":\ \"([^\"]*)\" ]] && active_title="${BASH_REMATCH[1]}"
[[ "${active_window_json}" =~ \"pid\":\ (-?[0-9]+) ]] && terminal_pid="${BASH_REMATCH[1]}"
shell_pid=""
cwd=""
shell_path=""
shell_entry=""
kitty_cwd=""
dolphin_dir="${active_title% — Dolphin}"

if [[ "${active_class}" == "org.kde.dolphin" && "${dolphin_dir}" == /* && -d "${dolphin_dir}" ]]; then
  printf '%s\n' "${dolphin_dir}"
  exit 0
fi

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

mapfile -t child_pids < <(pgrep -P "${terminal_pid}")
shell_pid="${child_pids[@]: -1}"

if [[ -n "${shell_pid}" ]]; then
  if cd -P "/proc/${shell_pid}/cwd" 2>/dev/null; then cwd="${PWD}"; fi
  shell_path="$(readlink "/proc/${shell_pid}/exe" 2>/dev/null || true)"

  if [[ -d "${cwd}" && -n "${shell_path}" && -r /etc/shells ]]; then
    while IFS= read -r shell_entry || [[ -n "${shell_entry}" ]]; do
      [[ "${shell_entry}" == "${shell_path}" ]] || continue
      printf '%s\n' "${cwd}"
      exit 0
    done </etc/shells
  fi
fi

printf '%s\n' "${HOME}"
