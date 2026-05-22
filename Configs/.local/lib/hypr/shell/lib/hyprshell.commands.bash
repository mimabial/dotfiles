#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Core command helpers for hyprshell.

hyprshell_builtin_commands() {
  printf '%s\n' \
    "--help" "help" "-h" \
    "-r" "reload" \
    "--version" "version" "-v" \
    "--release-notes" "release-notes" \
    "list" "--list-script" "--list-script-path" \
    "--completions" \
    "validate" "pyinit" "init" "lock-session" "logout" "pip" "pypr" "app"
}

initialized() {
  printf 'HYPR_SHELL_INIT=1\n'
  printf 'BIN_DIR=%q\n' "${BIN_DIR}"
  printf 'LIB_DIR=%q\n' "${LIB_DIR}"
  printf 'PATH=%q\n' "${PATH}"
  printf 'HYPR_SCRIPTS_PATH=%q\n' "${HYPR_SCRIPTS_PATH:-}"
  printf 'export BIN_DIR LIB_DIR PATH HYPR_SCRIPTS_PATH HYPR_SHELL_INIT\n'

  cat <<'EOT'
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || return 1 2>/dev/null || exit 1
hypr_runtime_bootstrap || return 1 2>/dev/null || exit 1
EOT
}

USAGE() {
  cat <<EOT
Usage: $(basename "$0") [command]
Commands:
  --help, help, -h              : Display this help message
  -r, reload                    : Reload Hyprland Environment
  release-notes                 : Show release notes
  completions [bash|zsh]        : Generate shell completions
  validate [args]               : Validate Hyprland configuration
  pyinit                        : Initialize python virtual environment
  version                       : Show version information
  init                          : Source initialization script
  list                          : List script entrypoints

Available commands:

$(list_script)

EOT
}

hyprreload() {
  print_log -sec "Hyprland" "Reloading Hyprland Environment"
  python_initialized
  run_lib_script "wallpaper/wallpaper.cache.sh" -t ""
  run_lib_script "theme/theme.switch.sh"
}

hyprlogout() {
  if uwsm check is-active; then
    uwsm stop
  elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]]; then
    hyprctl dispatch exit 0
  fi
}

lock_session() {
  # lock-session checks the screen-saver DBus service first.
  if busctl --user list | grep -q "org.freedesktop.ScreenSaver"; then
    echo "Using org.freedesktop.ScreenSaver for locking"
    loginctl lock-session
  else
    lock-screen.sh
  fi
}
