#!/usr/bin/env bash

menu_launch_shell_terminal() {
  menu_present_terminal --app-id org.tui.HyprShell --title HyprShell -- "$@"
}

menu_present_terminal() {
  local app_id="" title="" hypr_profile=""
  local -a hypr_cells=() hypr_size=() cmd=() launch_args=()

  while (($#)); do
    case "$1" in
      --app-id | --title | --hypr-profile)
        (($# > 1)) || return 2
        case "$1" in --app-id) app_id="$2" ;; --title) title="$2" ;; *) hypr_profile="$2" ;; esac
        shift 2 ;;
      --hypr-cells | --hypr-size)
        (($# > 2)) || return 2
        case "$1" in --hypr-cells) hypr_cells=("$2" "$3") ;; *) hypr_size=("$2" "$3") ;; esac
        shift 3 ;;
      --) shift; cmd+=("$@"); break ;;
      *) cmd+=("$1"); shift ;;
    esac
  done

  ((${#cmd[@]})) || return 0

  if [[ -n "${app_id}${title}${hypr_profile}" ]] || ((${#hypr_cells[@]} + ${#hypr_size[@]})); then
    [[ -n "${hypr_profile}" ]] && launch_args+=(--hypr-profile "${hypr_profile}")
    [[ "${#hypr_cells[@]}" -gt 0 ]] && launch_args+=(--hypr-cells "${hypr_cells[@]}")
    [[ "${#hypr_size[@]}" -gt 0 ]] && launch_args+=(--hypr-size "${hypr_size[@]}")
    launch_args+=(--app-id "${app_id:-org.tui.Terminal}" --title "${title:-Terminal}" -- "${cmd[@]}")
    hyprshell launch/terminal-present.sh "${launch_args[@]}"
  else
    hyprshell launch/terminal-present.sh -- "${cmd[@]}"
  fi
}

menu_edit_config() {
  dunstify -t "${NOTIFY_MS}" -i "text-editor" "Editing config file" "$1"
  hyprshell launch/editor.sh "$1"
}
