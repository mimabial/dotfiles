#!/usr/bin/env bash

#// set variables

# Toggle: if rofi is running for current user, kill it and exit
if pgrep -u "$USER" rofi >/dev/null 2>&1; then
  pkill -u "$USER" rofi
  exit 0
fi

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

rofi_config="$(rofi_resolve_theme style_1)"

font_scale="$(rofi_effective_font_scale "${ROFI_LAUNCH_SCALE}")"

rofi_args=(
  -show-icons
)

#// rofi action

case "${1}" in
  d | --drun)
    r_mode="drun"
    rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]:-}")
    rofi_args+=("-run-command" "app2unit.sh -- {cmd}")
    ;;
  w | --window)
    r_mode="window"
    rofi_args+=("${ROFI_LAUNCH_WINDOW_ARGS[@]:-}")
    ;;
  f | --filebrowser)
    r_mode="filebrowser"
    rofi_args+=("${ROFI_LAUNCH_FILEBROWSER_ARGS[@]:-}")
    ;;
  r | --run)
    r_mode="run"
    rofi_args+=("-run-command" "app2unit.sh -- {cmd}")
    rofi_args+=("${ROFI_LAUNCH_RUN_ARGS[@]:-}")
    ;;
  h | --help)
    echo -e "$(basename "${0}") [action]"
    echo "d :  drun mode"
    echo "w :  window mode"
    echo "f :  filebrowser mode,"
    echo "r :  run mode"
    exit 0
    ;;
  *)
    r_mode="drun"
    rofi_args+=("${ROFI_LAUNCH_DRUN_ARGS[@]:-}")
    rofi_args+=("-run-command" "app2unit.sh -- {cmd}")
    ;;
esac

#// wallpaper sizing (match window width to wallpaper aspect ratio)
rofi_theme_file="${rofi_config}"

width_override=""
margin_px="${ROFI_LAUNCH_MARGIN_PX:-${ROFI_LAUNCH_MARGIN:-0}}"
[[ "${margin_px}" =~ ^[0-9]+$ ]] || margin_px=0
width_override="$(rofi_wallpaper_width_override "${rofi_theme_file}" "${font_scale}" "${margin_px}")"

width_override_args=()
if [[ -n "${width_override}" ]]; then
  width_override_args=(-theme-str "${width_override}")
fi

#// set overrides
hypr_border="$(rofi_default_border_radius 10)"
hypr_width="$(rofi_default_border_width 2)"

if [[ -f "${HYPR_STATE_HOME}/fullscreen_${r_mode}" ]]; then
  hypr_width="0"
  hypr_border="0"
fi

elem_border="0"
[[ "${hypr_border}" -ne 0 ]] && elem_border=$((hypr_border * 2))

r_override="window {border: ${hypr_width}px; border-radius: ${hypr_border}px;} element {border-radius: ${elem_border}px;} button {border-radius: ${elem_border}px;}"

font_name="$(rofi_effective_font_name "${ROFI_LAUNCH_FONT:-$ROFI_FONT}")"
font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
i_override="$(rofi_icon_theme_override)"

rofi_args+=(
  -theme-str "${font_override}"
  -theme-str "${i_override}"
  -theme-str "${r_override}"
  "${width_override_args[@]}"
  -theme "${rofi_config}"
)

#// launch rofi
rofi -show "${r_mode}" "${rofi_args[@]}" &
disown
echo -show "${r_mode}" "${rofi_args[@]}"

# Cache fullscreen state after resolving the active launcher theme.

rofi -show "${r_mode}" \
  -show-icons \
  -config "${rofi_config}" \
  -theme-str "${font_override}" \
  -theme-str "${i_override}" \
  -theme-str "${r_override}" \
  -theme "${rofi_config}" \
  "${width_override_args[@]}" \
  -dump-theme \
  | { grep -q "fullscreen.*true" && touch "${HYPR_STATE_HOME}/fullscreen_${r_mode}"; } || rm -f "${HYPR_STATE_HOME}/fullscreen_${r_mode}"
