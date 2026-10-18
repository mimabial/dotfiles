#!/usr/bin/env bash

hyprshell_print_builtin_commands() {
  printf '%s\n' \
    "--help" "help" "-h" \
    "-r" "reload" \
    "--version" "version" "-v" \
    "--release-notes" "release-notes" \
    "list" "--list-script" "--list-script-path" \
    "--completions" "completions" \
    "pyinit" "init" "--init" "logout" "pip" "app" "resolve"
}

hyprshell_print_init_environment() {
  printf 'HYPR_SHELL_INIT=1\n'
  printf 'BIN_DIR=%q\n' "${BIN_DIR}"
  printf 'LIB_DIR=%q\n' "${LIB_DIR}"
  printf 'PATH=%q\n' "${PATH}"
  printf 'export BIN_DIR LIB_DIR PATH HYPR_SHELL_INIT\n'

  cat <<'EOT'
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || return 1 2>/dev/null || exit 1
hypr_runtime_load_shell_environment || return 1 2>/dev/null || exit 1
EOT
}

hyprshell_print_usage() {
  cat <<EOT
Usage: ${0##*/} [command]
Commands:
  --help, help, -h              : Display this help message
  -r, reload                    : Update Python packages, wallpaper caches and theme
  release-notes                 : Show release notes
  completions [bash|zsh]        : Generate shell completions
  pyinit                        : Create or update the managed Python environment
  version                       : Show version information
  init                          : Print shell initialization code
  list                          : List script entrypoints

Available commands:

$(hyprshell_print_script_names)

EOT
}

hyprshell_print_dotfiles_version() {
  local repo="${HYPR_DOTFILES_DIR:-$HOME/dotfiles}" version branch

  version="$(git -C "$repo" describe --tags --always 2>/dev/null)" || {
    printf 'Version unavailable\n' >&2
    return 1
  }
  branch="$(git -C "$repo" branch --show-current 2>/dev/null || true)"
  printf 'dotfiles %s (%s)\n' "$version" "${branch:-detached}"
}

hyprshell_print_dotfiles_changes() {
  local repo="${HYPR_DOTFILES_DIR:-$HOME/dotfiles}" tag notes

  tag="$(git -C "$repo" describe --tags --abbrev=0 2>/dev/null)" || {
    printf 'No release tags found\n'
    return 0
  }
  notes="$(git -C "$repo" log --format='• %s' "$tag"..HEAD)" || return 1
  printf 'Changes since %s:\n%s\n' "$tag" "${notes:-No commits since last release}"
}

hyprshell_refresh_python_wallpaper_and_theme() {
  print_log -sec "Hyprland" "Reloading Hyprland Environment"
  hyprshell_update_python_environment || return 1
  hyprshell_run_library_script "wallpaper/wallpaper.cache.sh" -t "" || return 1
  hyprshell_run_library_script "theme/theme.switch.sh"
}

hyprshell_exit_session() {
  if command -v uwsm >/dev/null && uwsm check is-active; then
    uwsm stop
  elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE}" ]]; then
    hypr_lua_dispatch 'hl.dsp.exit()'
  fi
}
