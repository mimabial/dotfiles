app_launch_mime_type() {
  if [[ "$1" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]; then
    printf 'x-scheme-handler/%s\n' "${1%%:*}"
  else
    xdg-mime query filetype "$1"
  fi
}

app_launch_resolve_open_target() {
  ((${#target_arguments[@]})) || app_launch_fail 'Open mode needs at least one file or URL'
  local arg mime current association=""
  for arg in "${target_arguments[@]}"; do
    mime="$(app_launch_mime_type "$arg")"
    [[ -n "$mime" ]] || app_launch_fail "Could not determine MIME type: $arg"
    current="$(xdg-mime query default "$mime")"
    [[ "$current" == *.desktop ]] || app_launch_fail "No application handles $mime"
    [[ -z "$association" || "$association" == "$current" ]] || app_launch_fail 'Files use different default applications'
    association="$current"
  done
  target_arguments=("$association" "${target_arguments[@]}")
}

app_launch_resolve_hyprshell_target() {
  ((${#target_arguments[@]})) || return 0
  [[ "${target_arguments[0]}" != *.desktop && "${target_arguments[0]}" != *.desktop:* ]] || return 0
  if [[ "${target_arguments[0]}" == */* ]]; then
    [[ -x "${target_arguments[0]}" ]] && return
  elif command -v "${target_arguments[0]}" >/dev/null 2>&1; then
    return
  fi
  local target
  target="$(hyprshell resolve "${target_arguments[0]}" 2>/dev/null)" || app_launch_fail "Command not found: ${target_arguments[0]}"
  target_arguments=(hyprshell "$target" "${target_arguments[@]:1}")
}

app_launch_apply_terminal() {
  $launch_in_terminal || return 0
  if ((${#target_arguments[@]})) && [[ "${target_arguments[0]}" == *.desktop || "${target_arguments[0]}" == *.desktop:* ]]; then
    source "$system_dir/applications/desktop-exec.bash"
    desktop_entry_exec_resolve "${target_arguments[@]}" || exit
    target_arguments=("${DESKTOP_ENTRY_ARGV[@]}")
  fi
  target_arguments=(tui-terminal-exec "${terminal_args[@]}" -- "${target_arguments[@]}")
}
