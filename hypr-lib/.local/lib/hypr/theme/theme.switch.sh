#!/usr/bin/env bash
# shellcheck disable=SC2154
# shellcheck disable=SC1091

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

[ -z "${HYPR_THEME}" ] && echo "ERROR: unable to detect theme" && exit 1
get_themes
confDir="${XDG_CONFIG_HOME:-$HOME/.config}"

# Set default HYPRLAND_CONFIG if not defined
HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr/hyprland.conf}"

# Lock file to prevent concurrent theme switching
THEME_SWITCH_LOCK="${XDG_RUNTIME_DIR:-/tmp}/theme-switch.lock"
exec 201>"${THEME_SWITCH_LOCK}"
! flock -n 201 && {
  print_log -sec "theme.switch" -stat "wait" "Another theme operation in progress, waiting..."
  flock 201
}
theme_notify_id=""
theme_notify_supports_p=""
theme_notify_tag="theme-switch"
theme_notify_active=false
theme_notify_app="Theme switch"
theme_notify_icon="preferences-desktop-theme"

cleanup_theme_switch() {
  local exit_code=$?
  theme_notify_finish "${exit_code}"
  flock -u 201 2>/dev/null
}
trap 'cleanup_theme_switch' EXIT

#// define functions

Theme_Change() {
  local x_switch=$1

  # shellcheck disable=SC2154
  for i in "${!thmList[@]}"; do
    if [ "${thmList[i]}" == "${HYPR_THEME}" ]; then
      if [ "${x_switch}" == 'n' ]; then
        setIndex=$(((i + 1) % ${#thmList[@]}))
      elif [ "${x_switch}" == 'p' ]; then
        setIndex=$((i - 1))
      fi
      themeSet="${thmList[setIndex]}"
      break
    fi
  done
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

load_hypr_variables() {
  local hypr_file="${1}"
  local hypr_file_normalized="${hypr_file}"
  local tmp_file=""

  # Check if hyq is available
  if ! command -v hyq &>/dev/null; then
    print_log -sec "theme" -warn "hyq not found" "theme variables won't be loaded from ${hypr_file}"
    return 1
  fi

  # Check if file exists
  if [[ ! -r "${hypr_file}" ]]; then
    print_log -sec "theme" -warn "file not readable" "${hypr_file}"
    return 1
  fi

  # Cache setup: use file path hash + mtime as cache key
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/hyq/cache"
  local file_hash file_mtime cache_key cache_file
  file_hash=$(echo -n "${hypr_file}" | md5sum | cut -d' ' -f1)
  file_mtime=$(stat -c %Y "${hypr_file}" 2>/dev/null || echo "0")
  cache_key="${file_hash}-${file_mtime}"
  cache_file="${cache_dir}/${cache_key}.cache"

  # Check cache hit
  if [[ -f "${cache_file}" ]]; then
    # shellcheck disable=SC1090
    source "${cache_file}"
    _apply_hypr_variables
    return 0
  fi

  # Cache miss - run hyq
  mkdir -p "${cache_dir}"

  # Normalize legacy theme keys (some themes used $GTK-THEME / $ICON-THEME)
  tmp_file="$(mktemp)"
  sed -E \
    -e 's/^\$GTK-THEME([[:space:]]*=)/$GTK_THEME\1/' \
    -e 's/^\$ICON-THEME([[:space:]]*=)/$ICON_THEME\1/' \
    -e "s/'\\$GTK-THEME'/'\\$GTK_THEME'/g" \
    -e "s/'\\$ICON-THEME'/'\\$ICON_THEME'/g" \
    "${hypr_file}" >"${tmp_file}"
  hypr_file_normalized="${tmp_file}"

  #? Load theme specific variables and cache the result
  local hyq_output
  hyq_output="$(
    hyq "${hypr_file_normalized}" \
      --export env \
      --allow-missing \
      -Q "\$GTK_THEME[string]" \
      -Q "\$ICON_THEME[string]" \
      -Q "\$CURSOR_THEME[string]" \
      -Q "\$CURSOR_SIZE" \
      -Q "\$FONT[string]" \
      -Q "\$FONT_SIZE" \
      -Q "\$FONT_STYLE[string]" \
      -Q "\$DOCUMENT_FONT[string]" \
      -Q "\$DOCUMENT_FONT_SIZE" \
      -Q "\$MONOSPACE_FONT[string]" \
      -Q "\$MONOSPACE_FONT_SIZE"
  )"
  rm -f "${tmp_file}"

  # Save to cache (atomic write)
  echo "${hyq_output}" >"${cache_file}.tmp" && mv "${cache_file}.tmp" "${cache_file}"

  # Clean old cache entries (keep last 20)
  find "${cache_dir}" -name "*.cache" -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | tail -n +21 | cut -d' ' -f2- | xargs -r rm -f

  eval "${hyq_output}"
  _apply_hypr_variables
}

# Helper to apply loaded variables (avoids duplication)
_apply_hypr_variables() {
  GTK_THEME=${__GTK_THEME:-$GTK_THEME}
  ICON_THEME=${__ICON_THEME:-$ICON_THEME}
  CURSOR_THEME=${__CURSOR_THEME:-$CURSOR_THEME}
  CURSOR_SIZE=${__CURSOR_SIZE:-$CURSOR_SIZE}
  TERMINAL=${__TERMINAL:-$TERMINAL}
  FONT=${__FONT:-$FONT}
  FONT_STYLE=${__FONT_STYLE:-''} # using hyprland this should be empty by default
  FONT_SIZE=${__FONT_SIZE:-$FONT_SIZE}
  DOCUMENT_FONT=${__DOCUMENT_FONT:-$DOCUMENT_FONT}
  DOCUMENT_FONT_SIZE=${__DOCUMENT_FONT_SIZE:-$DOCUMENT_FONT_SIZE}
  MONOSPACE_FONT=${__MONOSPACE_FONT:-$MONOSPACE_FONT}
  MONOSPACE_FONT_SIZE=${__MONOSPACE_FONT_SIZE:-$MONOSPACE_FONT_SIZE}
  BAR_FONT=${__BAR_FONT:-$BAR_FONT}
  MENU_FONT=${__MENU_FONT:-$MENU_FONT}
  NOTIFICATION_FONT=${__NOTIFICATION_FONT:-$NOTIFICATION_FONT}
}

# Batch write INI-style config files (single sed pass per file)
# Usage: ini_write_batch "file" "group1:key1=value1" "group2:key2=value2" ...
ini_write_batch() {
  local config_file="$1"
  shift
  local sed_args=()
  local groups_to_add=()
  declare -A group_keys

  # Ensure file exists
  [ ! -f "$config_file" ] && mkdir -p "$(dirname "$config_file")" && touch "$config_file"

  for entry in "$@"; do
    local group="${entry%%:*}"
    local rest="${entry#*:}"
    local key="${rest%%=*}"
    local value="${rest#*=}"

    # Build sed expression to update existing key or mark for addition
    sed_args+=(-e "/^\[${group}\]/,/^\[/ { s/^${key}=.*/${key}=${value}/ }")

    # Track group/key pairs for adding missing ones
    group_keys["${group}"]="${group_keys["${group}"]} ${key}=${value}"
  done

  # Apply existing key updates
  if [ ${#sed_args[@]} -gt 0 ]; then
    sed -i "${sed_args[@]}" "$config_file"
  fi

  # Add missing groups and keys
  for group in "${!group_keys[@]}"; do
    if ! grep -q "^\[${group}\]" "$config_file"; then
      echo -e "\n[${group}]" >>"$config_file"
    fi
    for kv in ${group_keys[$group]}; do
      local key="${kv%%=*}"
      if ! grep -q "^${key}=" "$config_file"; then
        sed -i "/^\[${group}\]/a ${kv}" "$config_file"
      fi
    done
  done
}

sanitize_hypr_theme() {
  input_file="${1}"
  output_file="${2}"
  buffer_file="$(mktemp)"

  sed '1d' "${input_file}" >"${buffer_file}"
  # Normalize legacy theme keys (some themes used $GTK-THEME / $ICON-THEME)
  sed -E -i \
    -e 's/^\$GTK-THEME([[:space:]]*=)/$GTK_THEME\1/' \
    -e 's/^\$ICON-THEME([[:space:]]*=)/$ICON_THEME\1/' \
    -e "s/'\\$GTK-THEME'/'\\$GTK_THEME'/g" \
    -e "s/'\\$ICON-THEME'/'\\$ICON_THEME'/g" \
    "${buffer_file}"
  # Define an array of patterns to remove
  # Supports regex patterns
  dirty_regex=(
    "^ *exec"
    "^ *decoration[^:]*: *drop_shadow"
    "^ *drop_shadow"
    "^ *decoration[^:]*: *shadow *="
    "^ *decoration[^:]*: *col.shadow* *="
    "^ *shadow_"
    "^ *col.shadow*"
    "^ *shadow:"
    "^ *col\\.active_border"
    "^ *col\\.inactive_border"
    "^ *col\\.border_"
  )

  dirty_regex+=("${HYPR_CONFIG_SANITIZE[@]}")

  # Loop through each pattern and remove matching lines
  for pattern in "${dirty_regex[@]}"; do
    grep -E "${pattern}" "${buffer_file}" | while read -r line; do
      sed -i "\|${line}|d" "${buffer_file}"
      print_log -sec "theme" -warn "sanitize" "${line}"
    done
  done
  cat "${buffer_file}" >"${output_file}"
  rm -f "${buffer_file}"

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

#// evaluate options
quiet=false
while getopts "qnps:" option; do
  case $option in

    n) # set next theme
      Theme_Change n
      export xtrans="grow"
      ;;

    p) # set previous theme
      Theme_Change p
      export xtrans="outer"
      ;;

    s) # set selected theme
      themeSet="$OPTARG" ;;
    q)
      quiet=true
      ;;
    *) # invalid option
      echo "... invalid option ..."
      echo "$(basename "${0}") -[option]"
      echo "n : set next theme"
      echo "p : set previous theme"
      echo "s : set input theme"
      exit 1
      ;;
  esac
done

#// update control file

# shellcheck disable=SC2076
[[ ! " ${thmList[*]} " =~ " ${themeSet} " ]] && themeSet="${HYPR_THEME}"

set_conf "HYPR_THEME" "${themeSet}"
print_log -sec "theme" -stat "apply" "${themeSet}"
theme_notify_start

export reload_flag=1
source "${LIB_DIR}/hypr/globalcontrol.sh"
[[ -f "${HYPR_CONFIG_HOME}/env-theme" ]] && source "${HYPR_CONFIG_HOME}/env-theme"

#// hypr
if [[ -r "${HYPRLAND_CONFIG}" ]]; then

  # shellcheck disable=SC2154
  # Updates the compositor theme data in advance
  [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]] && hyprctl keyword misc:disable_autoreload 1 -q
  [[ -r "${HYPR_THEME_DIR}/hypr.theme" ]] && sanitize_hypr_theme "${HYPR_THEME_DIR}/hypr.theme" "${XDG_CONFIG_HOME}/hypr/themes/theme.conf"

  #? Load theme specific variables
  load_hypr_variables "${HYPR_THEME_DIR}/hypr.theme"
  theme_gtk_theme="${__GTK_THEME:-}"
  theme_icon_theme="${__ICON_THEME:-}"

  #? Load User's hyprland overrides
  load_hypr_variables "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/hyprland.conf"

  # Keep theme-provided GTK/Icon theme if set (prevents config.toml defaults overriding theme packs)
  [[ -n "${theme_gtk_theme}" ]] && GTK_THEME="${theme_gtk_theme}"
  [[ -n "${theme_icon_theme}" ]] && ICON_THEME="${theme_icon_theme}"

fi

show_theme_status

# Early load the icon theme so that it is available for the rest of the script
if ! dconf write /org/gnome/desktop/interface/icon-theme "'${ICON_THEME}'"; then
  print_log -sec "theme" -warn "dconf" "failed to set icon theme"
fi

# legacy and directory resolution
if [ -d /run/current-system/sw/share/themes ]; then
  export themesDir=/run/current-system/sw/share/themes
fi

if [ ! -d "${themesDir}/${GTK_THEME}" ] && [ -d "$HOME/.themes/${GTK_THEME}" ]; then
  cp -rns "$HOME/.themes/${GTK_THEME}" "${themesDir}/${GTK_THEME}"
fi

#// qt5ct + qt6ct (batched)

QT5_FONT="${QT5_FONT:-${FONT}}"
QT5_FONT_SIZE="${QT5_FONT_SIZE:-${FONT_SIZE}}"
QT5_MONOSPACE_FONT="${QT5_MONOSPACE_FONT:-${MONOSPACE_FONT}}"
QT5_MONOSPACE_FONT_SIZE="${QT5_MONOSPACE_FONT_SIZE:-${MONOSPACE_FONT_SIZE:-9}}"
QT6_FONT="${QT6_FONT:-${FONT}}"
QT6_FONT_SIZE="${QT6_FONT_SIZE:-${FONT_SIZE}}"
QT6_MONOSPACE_FONT="${QT6_MONOSPACE_FONT:-${MONOSPACE_FONT}}"
QT6_MONOSPACE_FONT_SIZE="${QT6_MONOSPACE_FONT_SIZE:-${MONOSPACE_FONT_SIZE:-9}}"

ini_write_batch "${confDir}/qt5ct/qt5ct.conf" \
  "Appearance:icon_theme=${ICON_THEME}" \
  "Fonts:general=\"${QT5_FONT},${QT5_FONT_SIZE},-1,5,400,0,0,0,0,0,0,0,0,0,0,1,${FONT_STYLE}\"" \
  "Fonts:fixed=\"${QT5_MONOSPACE_FONT},${QT5_MONOSPACE_FONT_SIZE},-1,5,400,0,0,0,0,0,0,0,0,0,0,1\""

ini_write_batch "${confDir}/qt6ct/qt6ct.conf" \
  "Appearance:icon_theme=${ICON_THEME}" \
  "Fonts:general=\"${QT6_FONT},${QT6_FONT_SIZE},-1,5,400,0,0,0,0,0,0,0,0,0,0,1,${FONT_STYLE}\"" \
  "Fonts:fixed=\"${QT6_MONOSPACE_FONT},${QT6_MONOSPACE_FONT_SIZE:-9},-1,5,400,0,0,0,0,0,0,0,0,0,0,1\""

# // kde plasma (batched)

ini_write_batch "${confDir}/kdeglobals" \
  "Icons:Theme=${ICON_THEME}" \
  "General:TerminalApplication=${TERMINAL}" \
  "UiSettings:ColorScheme=colors" \
  "KDE:widgetStyle=kvantum"

# // The default cursor theme // fallback

ini_write_batch "${XDG_DATA_HOME}/icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}"
ini_write_batch "${HOME}/.icons/default/index.theme" "Icon Theme:Inherits=${CURSOR_THEME}"

# // gtk2

sed -i -e "/^gtk-theme-name=/c\gtk-theme-name=\"${GTK_THEME}\"" \
  -e "/^include /c\include \"$HOME/.gtkrc-2.0.mime\"" \
  -e "/^gtk-cursor-theme-name=/c\gtk-cursor-theme-name=\"${CURSOR_THEME}\"" \
  -e "/^gtk-icon-theme-name=/c\gtk-icon-theme-name=\"${ICON_THEME}\"" "$HOME/.gtkrc-2.0"

#// gtk3 (batched)

GTK3_FONT="${GTK3_FONT:-${FONT}}"
GTK3_FONT_SIZE="${GTK3_FONT_SIZE:-${FONT_SIZE}}"

ini_write_batch "${confDir}/gtk-3.0/settings.ini" \
  "Settings:gtk-theme-name=${GTK_THEME}" \
  "Settings:gtk-icon-theme-name=${ICON_THEME}" \
  "Settings:gtk-cursor-theme-name=${CURSOR_THEME}" \
  "Settings:gtk-cursor-theme-size=${CURSOR_SIZE}" \
  "Settings:gtk-font-name=${GTK3_FONT} ${GTK3_FONT_SIZE}"

#// gtk4
if [ -d "${themesDir}/${GTK_THEME}/gtk-4.0" ]; then
  gtk4Theme="${GTK_THEME}"
else
  gtk4Theme="Pywal16-Gtk"
  print_log -sec "theme" -stat "use" "'Pywal16-Gtk' as gtk4 theme"
fi
rm -rf "${confDir}/gtk-4.0"
if [ -d "${themesDir}/${gtk4Theme}/gtk-4.0" ]; then
  ln -s "${themesDir}/${gtk4Theme}/gtk-4.0" "${confDir}/gtk-4.0"
else
  print_log -sec "theme" -warn "gtk4" "theme directory '${themesDir}/${gtk4Theme}/gtk-4.0' does not exist"
fi

#// flatpak GTK

if pkg_installed flatpak; then
  flatpak \
    --user override \
    --filesystem="${themesDir}" \
    --filesystem="$HOME/.themes" \
    --filesystem="$HOME/.icons" \
    --filesystem="$HOME/.local/share/icons" \
    --env=GTK_THEME="${gtk4Theme}" \
    --env=ICON_THEME="${ICON_THEME}"

  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &

fi
# // xsettingsd

sed -i -e "/^Net\/ThemeName /c\Net\/ThemeName \"${GTK_THEME}\"" \
  -e "/^Net\/IconThemeName /c\Net\/IconThemeName \"${ICON_THEME}\"" \
  -e "/^Gtk\/CursorThemeName /c\Gtk\/CursorThemeName \"${CURSOR_THEME}\"" \
  -e "/^Gtk\/CursorThemeSize /c\Gtk\/CursorThemeSize ${CURSOR_SIZE}" \
  "$confDir/xsettingsd/xsettingsd.conf"

# // Legacy themes using ~/.themes also fixed GTK4 not following xdg

if [ ! -L "$HOME/.themes/${GTK_THEME}" ] && [ -d "${themesDir}/${GTK_THEME}" ]; then
  print_log -sec "theme" -warn "linking" "${GTK_THEME} to ~/.themes to fix GTK4 not following xdg"
  mkdir -p "$HOME/.themes"
  rm -rf "$HOME/.themes/${GTK_THEME}"
  ln -snf "${themesDir}/${GTK_THEME}" "$HOME/.themes/"
fi

# // .Xresources
if [ -f "$HOME/.Xresources" ]; then
  sed -i -e "/^Xcursor\.theme:/c\Xcursor.theme: ${CURSOR_THEME}" \
    -e "/^Xcursor\.size:/c\Xcursor.size: ${CURSOR_SIZE}" "$HOME/.Xresources"

  # Add if they don't exist
  grep -q "^Xcursor\.theme:" "$HOME/.Xresources" || echo "Xcursor.theme: ${CURSOR_THEME}" >>"$HOME/.Xresources"
  grep -q "^Xcursor\.size:" "$HOME/.Xresources" || echo "Xcursor.size: 30" >>"$HOME/.Xresources"
else
  # Create .Xresources if it doesn't exist
  cat >"$HOME/.Xresources" <<EOF
Xcursor.theme: ${CURSOR_THEME}
Xcursor.size: ${CURSOR_SIZE}
EOF
fi

# // .Xdefaults

if [ -f "$HOME/.Xdefaults" ]; then
  sed -i -e "/^Xcursor\.theme:/c\Xcursor.theme: ${CURSOR_THEME}" \
    -e "/^Xcursor\.size:/c\Xcursor.size: ${CURSOR_SIZE}" "$HOME/.Xdefaults"

  # Add if they don't exist
  grep -q "^Xcursor\.theme:" "$HOME/.Xdefaults" || echo "Xcursor.theme: ${CURSOR_THEME}" >>"$HOME/.Xdefaults"
  grep -q "^Xcursor\.size:" "$HOME/.Xdefaults" || echo "Xcursor.size: 30" >>"$HOME/.Xdefaults"
fi

#? Workaround for gtk-4 having settings.ini!
if [ -f "${confDir}/gtk-4.0/settings.ini" ]; then
  rm "${confDir}/gtk-4.0/settings.ini"
fi

#// wallpaper
export -f pkg_installed

[[ -d "$WALLPAPER_CURRENT_DIR" ]] && find -H "$WALLPAPER_CURRENT_DIR" -name "*.png" -exec sh -c '
    for file; do
        base=$(basename "$file" .png)
        if pkg_installed ${base}; then
            "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" --link --backend "${base}"
        fi
    done
' sh {} + &

if [ "$quiet" = true ]; then
  "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" -s "$(readlink "${HYPR_THEME_DIR}/wall.set")" --global >/dev/null 2>&1
else
  "${LIB_DIR}/hypr/wallpaper/wallpaper.sh" -s "$(readlink "${HYPR_THEME_DIR}/wall.set")" --global
fi
