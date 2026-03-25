#!/usr/bin/env bash

run_pacman_privileged() {
  local -a pacman_args=("$@")

  if [[ -t 0 && -t 1 ]] && command -v sudo >/dev/null 2>&1; then
    sudo pacman "${pacman_args[@]}"
    return $?
  fi

  if command -v pkexec >/dev/null 2>&1; then
    pkexec pacman "${pacman_args[@]}"
    return $?
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo pacman "${pacman_args[@]}"
    return $?
  fi

  echo "Neither pkexec nor sudo is available." >&2
  return 1
}
