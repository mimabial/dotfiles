#!/usr/bin/env sh

hypr_cursor_value() {
  var_name="$1"
  file="$2"

  sed -n "s/^[[:space:]]*\\\$${var_name}[[:space:]]*=[[:space:]]*//p" "$file" 2>/dev/null |
    tail -n 1 |
    sed "s/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^['\"]//; s/['\"]$//"
}

HYPR_THEME_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.meta"

if [ -r "$HYPR_THEME_CONF" ]; then
  _hypr_cursor_theme="$(hypr_cursor_value CURSOR_THEME "$HYPR_THEME_CONF")"
  _hypr_cursor_size="$(hypr_cursor_value CURSOR_SIZE "$HYPR_THEME_CONF")"

  [ -n "$_hypr_cursor_theme" ] && XCURSOR_THEME="$_hypr_cursor_theme"
  [ -n "$_hypr_cursor_size" ] && XCURSOR_SIZE="$_hypr_cursor_size"
fi

XCURSOR_THEME="${XCURSOR_THEME:-Bibata-Modern-Ice}"
XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
XCURSOR_PATH="${XCURSOR_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/icons:$HOME/.icons:/usr/share/icons}"

for _hypr_cursor_env in XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH; do
  case " ${UWSM_FINALIZE_VARNAMES:-} " in
    *" $_hypr_cursor_env "*) ;;
    *) UWSM_FINALIZE_VARNAMES="${UWSM_FINALIZE_VARNAMES:-} $_hypr_cursor_env" ;;
  esac
done

export XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH UWSM_FINALIZE_VARNAMES

unset HYPR_THEME_CONF _hypr_cursor_theme _hypr_cursor_size _hypr_cursor_env
