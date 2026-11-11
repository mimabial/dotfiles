HYPR_THEME_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.meta"

hypr_cursor_values() {
  awk '
    /^[[:space:]]*[$]CURSOR_(THEME|SIZE)[[:space:]]*=/ {
      name = $0
      sub(/^[[:space:]]*[$]/, "", name)
      sub(/[[:space:]]*=.*/, "", name)
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      sub(/[[:space:]]*#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      sub(/^["\047]/, "", value)
      sub(/["\047]$/, "", value)
      values[name] = value
    }
    END { print values["CURSOR_THEME"]; print values["CURSOR_SIZE"] }
  ' "$1" 2>/dev/null
}

if [ -r "$HYPR_THEME_CONF" ]; then
  { IFS= read -r _hypr_cursor_theme; IFS= read -r _hypr_cursor_size; } <<CURSOR_VALUES
$(hypr_cursor_values "$HYPR_THEME_CONF")
CURSOR_VALUES

  [ -n "$_hypr_cursor_theme" ] && XCURSOR_THEME="$_hypr_cursor_theme"
  [ -n "$_hypr_cursor_size" ] && XCURSOR_SIZE="$_hypr_cursor_size"
fi

XCURSOR_THEME="${XCURSOR_THEME:-Bibata-Modern-Ice}"
XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
XCURSOR_PATH="${XCURSOR_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/icons:$HOME/.icons:/usr/share/icons}"
HYPRCURSOR_THEME="${HYPRCURSOR_THEME:-$XCURSOR_THEME}"
HYPRCURSOR_SIZE="${HYPRCURSOR_SIZE:-$XCURSOR_SIZE}"

for _hypr_cursor_env in XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH HYPRCURSOR_THEME HYPRCURSOR_SIZE; do
  case " ${UWSM_FINALIZE_VARNAMES:-} " in
    *" $_hypr_cursor_env "*) ;;
    *) UWSM_FINALIZE_VARNAMES="${UWSM_FINALIZE_VARNAMES:-} $_hypr_cursor_env" ;;
  esac
done

export XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH HYPRCURSOR_THEME HYPRCURSOR_SIZE UWSM_FINALIZE_VARNAMES

unset HYPR_THEME_CONF _hypr_cursor_theme _hypr_cursor_size _hypr_cursor_env
