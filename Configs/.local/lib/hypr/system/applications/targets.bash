app_launch_mime_type() {
  if [[ "$1" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]; then
    printf 'x-scheme-handler/%s\n' "${1%%:*}"
  else
    xdg-mime query filetype "$1"
  fi
}

app_launch_resolve_open_target() {
  local -n open_arguments_ref="$1"
  ((${#open_arguments_ref[@]})) || app_launch_die 'Open mode needs at least one file or URL'
  local arg mime current association=""
  for arg in "${open_arguments_ref[@]}"; do
    mime="$(app_launch_mime_type "$arg")"
    [[ -n "$mime" ]] || app_launch_die "Could not determine MIME type: $arg"
    current="$(xdg-mime query default "$mime")"
    [[ "$current" == *.desktop ]] || app_launch_die "No application handles $mime"
    [[ -z "$association" || "$association" == "$current" ]] || app_launch_die 'Files use different default applications'
    association="$current"
  done
  open_arguments_ref=("$association" "${open_arguments_ref[@]}")
}

app_launch_resolve_hyprshell_target() {
  local -n command_arguments_ref="$1"
  ((${#command_arguments_ref[@]})) || return 0
  [[ "${command_arguments_ref[0]}" != *.desktop && "${command_arguments_ref[0]}" != *.desktop:* ]] || return 0
  if [[ "${command_arguments_ref[0]}" == */* ]]; then
    [[ -x "${command_arguments_ref[0]}" ]] && return
  elif command -v "${command_arguments_ref[0]}" >/dev/null 2>&1; then
    return
  fi
  local target
  target="$(hyprshell resolve "${command_arguments_ref[0]}" 2>/dev/null)" || app_launch_die "Command not found: ${command_arguments_ref[0]}"
  command_arguments_ref=(hyprshell "$target" "${command_arguments_ref[@]:1}")
}

app_launch_apply_terminal() {
  local -n terminal_target_ref="$1"
  $launch_in_terminal || return 0
  if ((${#terminal_target_ref[@]})) && [[ "${terminal_target_ref[0]}" == *.desktop || "${terminal_target_ref[0]}" == *.desktop:* ]]; then
    source "$system_dir/applications/desktop-exec.bash"
    local entry_workdir=""
    desktop_entry_exec_resolve_into terminal_target_ref entry_workdir "${terminal_target_ref[@]}" || exit
  fi
  terminal_target_ref=(tui-terminal-exec "${terminal_args[@]}" -- "${terminal_target_ref[@]}")
}
