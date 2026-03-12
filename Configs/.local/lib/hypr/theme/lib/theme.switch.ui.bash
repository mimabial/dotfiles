#!/usr/bin/env bash

# Shared UI/notifier helpers for theme.switch.sh.

Theme_Change() {
  local x_switch="$1"

  # Validate input parameter
  if [[ ! "${x_switch}" =~ ^[np]$ ]]; then
    print_log -sec "theme" -err "Theme_Change" "invalid direction '${x_switch}' (expected 'n' or 'p')"
    return 1
  fi

  # shellcheck disable=SC2154
  local found=false
  for i in "${!thmList[@]}"; do
    if [ "${thmList[i]}" == "${HYPR_THEME}" ]; then
      found=true
      if [ "${x_switch}" == 'n' ]; then
        setIndex=$(((i + 1) % ${#thmList[@]}))
      elif [ "${x_switch}" == 'p' ]; then
        setIndex=$((i - 1))
        # Handle negative wrap-around
        [[ ${setIndex} -lt 0 ]] && setIndex=$((${#thmList[@]} - 1))
      fi
      themeSet="${thmList[setIndex]}"
      break
    fi
  done

  if [[ "${found}" != true ]]; then
    print_log -sec "theme" -warn "Theme_Change" "current theme '${HYPR_THEME}' not found in theme list"
    # Default to first theme
    setIndex=0
    themeSet="${thmList[0]}"
  fi
}

show_theme_status() {
  cat <<EOF
Current theme: ${HYPR_THEME}
Gtk theme: ${GTK_THEME}
Icon theme: ${ICON_THEME}
Cursor theme: ${CURSOR_THEME}
Cursor size: ${CURSOR_SIZE}
Terminal: ${TERMINAL}
Font: ${FONT}
Font style: ${FONT_STYLE}
Font size: ${FONT_SIZE}
Document font: ${DOCUMENT_FONT}
Document font size: ${DOCUMENT_FONT_SIZE}
Monospace font: ${MONOSPACE_FONT}
Monospace font size: ${MONOSPACE_FONT_SIZE}
Bar font: ${BAR_FONT}
Menu font: ${MENU_FONT}
Notification font: ${NOTIFICATION_FONT}

EOF
}

theme_notify_send() {
  local title="$1"
  local body="$2"
  local timeout="$3"

  [[ -z "${quiet}" ]] && quiet=false
  [[ "${quiet}" == true ]] && return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  [[ -z "${timeout}" ]] && timeout=1500

  local args=(
    -a "${theme_notify_app}"
    -i "${theme_notify_icon}"
    -t "${timeout}"
    -h "string:x-canonical-private-synchronous:${theme_notify_tag}"
  )
  [[ -n "${theme_notify_id}" ]] && args+=(-r "${theme_notify_id}")

  if [[ -z "${theme_notify_supports_p}" ]]; then
    if notify-send --help 2>&1 | grep -q -- "--print-id"; then
      theme_notify_supports_p=true
    else
      theme_notify_supports_p=false
    fi
  fi

  if [[ "${theme_notify_supports_p}" == true ]]; then
    local new_id=""
    new_id="$(notify-send -p "${args[@]}" "${title}" "${body}" 2>/dev/null)" || {
      notify-send "${args[@]}" "${title}" "${body}" &
      return 0
    }
    new_id="${new_id//$'\n'/}"
    [[ -n "${new_id}" ]] && theme_notify_id="${new_id}"
  else
    notify-send "${args[@]}" "${title}" "${body}" &
  fi
}

theme_notify_clear() {
  local theme_name="${themeSet}"
  [[ -z "${theme_name}" ]] && theme_name="${HYPR_THEME}"
  theme_notify_send "Theme switched" "${theme_name}" 800
}

theme_notify_start() {
  local theme_name="${themeSet}"
  [[ -z "${theme_name}" ]] && theme_name="${HYPR_THEME}"
  theme_notify_send "Switching theme" "${theme_name}" 0
  theme_notify_active=true
}

theme_notify_finish() {
  local exit_code="$1"
  [[ "${theme_notify_active}" == true ]] || return 0
  theme_notify_active=false
  [[ -z "${exit_code}" ]] && exit_code=0

  local theme_name="${themeSet}"
  [[ -z "${theme_name}" ]] && theme_name="${HYPR_THEME}"

  if [[ "${exit_code}" -eq 0 ]]; then
    theme_notify_clear
  else
    theme_notify_send "Theme switch interrupted" "${theme_name}" 2500
  fi
}
