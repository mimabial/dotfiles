#!/usr/bin/env bash
#
# browser.sh — Launch the default web browser; passes --private through as the browser-specific private-mode flag.
#
# Usage: browser.sh [--private] [browser-args...]
#
# Depends on: xdg-settings, setsid, uwsm-app, ${HYPR_LIB_DIR}/system/desktop-entry.exec.bash
#

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell launch/browser [--private] [browser-args...]
Launch the default web browser; --private maps to its private/incognito flag." "$@"

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/desktop-entry.exec.bash"

default_browser="$(xdg-settings get default-web-browser)"
desktop_entry_exec_resolve "${default_browser}" || exit 1

case "${DESKTOP_ENTRY_EXECUTABLE}" in
  firefox | librewolf) private_flag="--private-window" ;;
  *)                   private_flag="--incognito"      ;;
esac

launch_args=()
for arg in "$@"; do
  if [[ "${arg}" == "--private" ]]; then
    launch_args+=("${private_flag}")
  else
    launch_args+=("${arg}")
  fi
done

[[ -z "${DESKTOP_ENTRY_WORKDIR}" ]] || cd "${DESKTOP_ENTRY_WORKDIR}" || exit 1

exec setsid uwsm-app -- "${DESKTOP_ENTRY_ARGV[@]}" "${launch_args[@]}"
