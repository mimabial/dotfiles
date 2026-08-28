#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require rofi || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

hypr_help_guard "Usage: hyprshell keybinds/app-hints <kitty|tmux>
Read-only keybinding cheatsheet for an app, in rofi.
Hyprland's own cheatsheet is keybinds/keybinds_hint, which can also run a bind." "$@"

if hypr_user_pgrep -x rofi >/dev/null 2>&1; then
  hypr_user_pkill -x rofi
  exit 0
fi

# tmux resolves its own bindings, notes and prefix, so ask it rather than
# re-parsing a config full of key tables and line continuations
tmux_binds() {
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  local listing=""

  listing="$(tmux list-keys -N 2>/dev/null || true)"
  if [[ -z "${listing}" && -f "${conf}" ]]; then
    listing="$(tmux -f "${conf}" start-server \; list-keys -N \; kill-server 2>/dev/null || true)"
  fi
  [[ -n "${listing}" ]] || return 1
  sed -E 's/[[:space:]]{2,}/\t/' <<<"${listing}"
}

# kitty has no resolved-keymap dump in this build, so read the config layers
kitty_binds() {
  local conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
  local -a confs=("${conf_dir}"/*.conf)

  [[ -e "${confs[0]}" ]] || return 1
  awk '
    /^[ \t]*map[ \t]/ {
      line = $0
      sub(/^[ \t]*map[ \t]+/, "", line)
      cond = ""
      if (line ~ /^--when-focus-on[ \t]+/) {
        sub(/^--when-focus-on[ \t]+/, "", line)
        split(line, parts, " ")
        cond = " (" parts[1] ")"
        sub(/^[^ \t]+[ \t]+/, "", line)
      }
      split(line, parts, " ")
      key = parts[1]
      action = substr(line, length(key) + 2)
      if (action == "") action = "passed through to the app"
      print key "\t" action cond
    }
  ' "${confs[@]}"
}

app="${1:-}"
case "${app}" in
  kitty) binds="$(kitty_binds || true)" ;;
  tmux) binds="$(tmux_binds || true)" ;;
  *) printf 'usage: %s <kitty|tmux>\n' "$(basename "$0")" >&2; exit 1 ;;
esac

if [[ -z "${binds}" ]]; then
  dunstify -t 5000 -i dialog-error "Keybind hints" "No ${app} bindings found."
  exit 0
fi

rows="$(awk -F '\t' '{ printf "%-24s >   %s\n", $1, $2 }' <<<"${binds}")"
font_scale="$(rofi_effective_font_scale "${ROFI_KEYBIND_HINT_SCALE:-}")"
font_name="$(rofi_effective_font_name "${ROFI_KEYBIND_HINT_FONT:-${ROFI_FONT:-}}")"

# same geometry and overrides as keybinds_hint, so the cheatsheets match
printf '%s\n' "${rows}" | rofi -dmenu -i -no-custom -no-show-icons -p " ${app}" \
  -theme "$(rofi_resolve_theme "${ROFI_KEYBIND_HINT_STYLE:-clipboard}")" \
  -theme-str "entry { placeholder: \"  Keybindings\"; }" \
  -theme-str "$(rofi_font_override "${font_name}" "${font_scale}")" \
  -theme-str "$(rofi_icon_theme_override)" \
  -theme-str "$(rofi_standard_window_theme listview same)" \
  -theme-str "$(rofi_cheatsheet_layout_override "$(wc -l <<<"${rows}")" "${font_name}" "${font_scale}")" \
  >/dev/null
