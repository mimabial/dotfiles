#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

hyprshell_builtin_commands() {
  printf '%s\n' \
    "--help" "help" "-h" \
    "-r" "reload" \
    "--version" "version" "-v" \
    "--release-notes" "release-notes" \
    "list" "--list-script" "--list-script-path" \
    "--completions" "completions" \
    "pyinit" "init" "--init" "lock-session" "logout" "pip" "pypr" "app" "resolve"
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

usage() {
  cat <<EOT
Usage: ${0##*/} [command]
Commands:
  --help, help, -h              : Display this help message
  -r, reload                    : Reload Hyprland Environment
  release-notes                 : Show release notes
  completions [bash|zsh]        : Generate shell completions
  pyinit                        : Initialize python virtual environment
  version                       : Show version information
  init                          : Source initialization script
  list                          : List script entrypoints

Available commands:

$(list_script)

EOT
}

get_version() {
  local repo="${HYPR_DOTFILES_DIR:-$HOME/dotfiles}" version branch

  version="$(git -C "$repo" describe --tags --always 2>/dev/null)" || {
    printf 'Version unavailable\n' >&2
    return 1
  }
  branch="$(git -C "$repo" branch --show-current 2>/dev/null || true)"
  printf 'dotfiles %s (%s)\n' "$version" "${branch:-detached}"
}

get_release_notes() {
  local repo="${HYPR_DOTFILES_DIR:-$HOME/dotfiles}" tag notes

  tag="$(git -C "$repo" describe --tags --abbrev=0 2>/dev/null)" || {
    printf 'No release tags found\n'
    return 0
  }
  notes="$(git -C "$repo" log --format='• %s' "$tag"..HEAD)" || return 1
  printf 'Changes since %s:\n%s\n' "$tag" "${notes:-No commits since last release}"
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
    hypr_lua_dispatch 'hl.dsp.exit()'
  fi
}

lock_session() {
  if busctl --user list | grep -q "org.freedesktop.ScreenSaver"; then
    echo "Using org.freedesktop.ScreenSaver for locking"
    loginctl lock-session
  else
    lock-screen.sh
  fi
}
