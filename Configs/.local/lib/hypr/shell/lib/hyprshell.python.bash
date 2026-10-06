#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

python_initialized() {
  python "${LIB_DIR}/hypr/pyutils/pip_env.py" rebuild
}

python_activate() {
  local python_env="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/pip_env/bin/activate"
  if [[ -r "${python_env}" ]]; then
    # shellcheck disable=SC1090
    source "${python_env}"
  else
    printf "Warning: Python virtual environment not found at %s\n" "${python_env}"
    printf "You may need to run 'hyprshell pyinit' to set it up.\n"
    python_initialized || return 1
    source "${python_env}"
  fi
}

run_pip() {
  python_activate
  shift
  pip "$@"
}
