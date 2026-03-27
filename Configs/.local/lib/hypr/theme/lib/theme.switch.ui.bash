#!/usr/bin/env bash

# Shared UI/notifier helpers for theme.switch.sh.

select_adjacent_theme() {
  local direction="$1"

  # Validate input parameter
  if [[ ! "${direction}" =~ ^[np]$ ]]; then
    print_log -sec "theme" -err "select_adjacent_theme" "invalid direction '${direction}' (expected 'n' or 'p')"
    return 1
  fi

  # shellcheck disable=SC2154
  local found=false
  for i in "${!thmList[@]}"; do
    if [ "${thmList[i]}" == "${HYPR_THEME}" ]; then
      found=true
      if [ "${direction}" == 'n' ]; then
        setIndex=$(((i + 1) % ${#thmList[@]}))
      elif [ "${direction}" == 'p' ]; then
        setIndex=$((i - 1))
        # Handle negative wrap-around
        [[ ${setIndex} -lt 0 ]] && setIndex=$((${#thmList[@]} - 1))
      fi
      themeSet="${thmList[setIndex]}"
      break
    fi
  done

  if [[ "${found}" != true ]]; then
    print_log -sec "theme" -warn "select_adjacent_theme" "current theme '${HYPR_THEME}' not found in theme list"
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
Groupbar font: ${GROUPBAR_FONT}

EOF
}

theme_notify_finish() {
  local exit_code="$1"
  [[ -z "${quiet}" ]] && quiet=false
  [[ "${quiet}" == true ]] && return 0
  [[ -z "${exit_code}" ]] && exit_code=0
  [[ "${exit_code}" -eq 0 ]] && return 0
  command -v dunstify >/dev/null 2>&1 || return 0

  local theme_name="${themeSet}"
  [[ -z "${theme_name}" ]] && theme_name="${HYPR_THEME}"

  dunstify -a "Theme switch" -i "preferences-desktop-theme" -t 2500 \
    "Theme switch interrupted" "${theme_name}" >/dev/null 2>&1 || true
}
