#!/usr/bin/env bash

menu_pick_language() {
  local action="$1" parent="$2" empty_label="No languages" script="${HYPR_LIB_DIR}/system/language.sh"
  local rows="" selection=""

  rows="$("${script}" "${action}")"
  selection="$(menu "${action^} Language" "${rows:-${empty_label}}" --select "$("${script}" current "${action}")")"
  case "${selection}" in
    "${empty_label}" | "") menu_exit_or_show "${parent}" ;;
  esac
  case "${action}" in
    install | remove) menu_present_terminal --hypr-profile dialog --app-id org.language.Manage --title "${action^} Language" -- hyprshell system/language "${action}" "${selection##* }" ;;
    *) dunstify -a Language -i preferences-desktop-locale "${action^} language" "$("${script}" "${action}" "${selection##* }" 2>&1)" ;;
  esac
}
