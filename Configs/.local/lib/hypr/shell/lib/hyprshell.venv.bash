#!/usr/bin/env bash

hyprshell_update_python_environment() {
  python "${LIB_DIR}/hypr/pyutils/manage_venv.py" rebuild
}

hyprshell_ensure_and_activate_python_environment() {
  local activation_script="${HYPR_STATE_HOME}/pip_env/bin/activate"
  if [[ ! -r "${activation_script}" ]]; then
    printf "Warning: Python virtual environment not found at %s\n" "${activation_script}"
    printf "You may need to run 'hyprshell pyinit' to set it up.\n"
    hyprshell_update_python_environment || return 1
  fi
  # shellcheck disable=SC1090
  source "${activation_script}"
}

hyprshell_run_managed_pip() {
  hyprshell_ensure_and_activate_python_environment || return 1
  pip "$@"
}
