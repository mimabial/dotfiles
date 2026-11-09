#!/usr/bin/env bash
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell launch/browser [--private] [browser-args...]
Launch the default web browser; --private maps to its private/incognito flag." "$@"

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/applications/desktop-exec.bash"

default_browser="$(xdg-settings get default-web-browser)"
browser_argv=() browser_workdir=""
desktop_entry_exec_resolve_into browser_argv browser_workdir "${default_browser}" || exit 1

case "${browser_argv[0]##*/}" in
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

[[ -z "${browser_workdir}" ]] || cd "${browser_workdir}" || exit 1

exec "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/app2unit.sh" -- "${browser_argv[@]}" "${launch_args[@]}"
