#!/usr/bin/env bash

# Core command helpers for hyprshell.

initialized() {
  cat <<EOT
HYPR_SHELL_INIT=1
BIN_DIR="${BIN_DIR}"
LIB_DIR="${LIB_DIR}"
PATH=${PATH}
HYPR_SCRIPTS_PATH=${HYPR_SCRIPTS_PATH}
export BIN_DIR LIB_DIR PATH HYPR_SCRIPTS_PATH HYPR_SHELL_INIT
EOT

  # Remove shebang hints to avoid conflicts with eval.
  command cat "${LIB_DIR}/hypr/globalcontrol.sh" | sed '1{/^#!/d;}'
}

USAGE() {
  cat <<EOT
Usage: $(basename "$0") [command]
Commands:
  --help, help, -h              : Display this help message
  -r, reload                    : Reload Hyprland Environment
  release-notes                 : Show release notes
  completions [bash|zsh|fish]   : Generate shell completions
  validate [args]               : Validate Hyprland configuration
  pyinit                        : Initialize python virtual environment
  version                       : Show version information
  init                          : Source initialization script

Available commands:

$(list_script)

EOT
}

hyprreload() {
  print_log -sec "Hyprland" "Reloading Hyprland Environment"
  python_initialized
  run_lib_script "wallpaper/swwwallcache.sh" -t ""
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
    lockscreen.sh
  fi
}
