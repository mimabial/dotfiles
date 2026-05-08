#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Python environment and pypr/pip helpers for hyprshell.

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
    python_initialized
  fi
}

run_pip() {
  python_activate
  shift
  pip "$@"
}

hyprshell_socket_send() {
  local socket_path="$1"
  local message_string="$2"
  local socket_client=""

  for socket_client in nc socat ncat; do
    command -v "${socket_client}" >/dev/null 2>&1 || continue
    case "${socket_client}" in
      nc)
        printf '%s' "${message_string}" | nc -N -U "${socket_path}" 2>/dev/null
        ;;
      socat)
        printf '%s' "${message_string}" | socat - UNIX-CONNECT:"${socket_path}" 2>/dev/null
        ;;
      ncat)
        printf '%s' "${message_string}" | ncat -U "${socket_path}" 2>/dev/null
        ;;
    esac && return 0
  done

  return 1
}

run_pypr() {
  python_activate
  shift

  if command -v pypr >/dev/null 2>&1; then
    local socket_path="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.pyprland.sock"
    local pypr_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/pyprland.toml"

    if [[ ! -f "${pypr_conf}" ]]; then
      notify_send_safe "Missing pyprland.toml" "Please create ${pypr_conf} to configure PyPR."
      exit 1
    fi

    local -a message_args=("$@")
    [[ ${#message_args[@]} -eq 0 ]] && message_args=("help")
    local message_string="${message_args[*]}"

    if [[ -S "${socket_path}" ]] && pgrep -u "${USER}" pypr >/dev/null 2>&1; then
      if ! hyprshell_socket_send "${socket_path}" "${message_string}"; then
        if ! pypr "${message_args[@]}"; then
          print_log -sec "pypr" "Error communicating with socket: ${socket_path}"
          exit 1
        fi
      fi
    else
      print_log -sec "pypr" "PyPR is not running properly, starting fresh"
      [[ -S "${socket_path}" ]] && print_log -y "Removing stale socket: ${socket_path}"
      pgrep -u "${USER}" pypr >/dev/null && print_log -y "Killing existing pypr process"
      rm -f "${socket_path}"

      exec "${HYPR_LIB_DIR}/system/app2unit.sh" -t service pypr
    fi
  else
    pip install --no-input pyprland==2.4.7
  fi
}
