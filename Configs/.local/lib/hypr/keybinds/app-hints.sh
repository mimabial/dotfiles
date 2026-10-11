#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require rofi || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"

hypr_help_guard "Usage: hyprshell keybinds/app-hints <kitty|tmux>
Read-only keybinding cheatsheet for an app, in rofi.
Hyprland's own cheatsheet is keybinds/keybinds_hint, which can also run a bind." "$@"

if hypr_user_pgrep -x rofi >/dev/null 2>&1; then
  hypr_user_pkill -x rofi
  exit 0
fi

# tmux resolves its own bindings, notes and prefix, so ask it rather than
# re-parsing a config full of key tables and line continuations
list_tmux_bindings() {
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  local key_and_note_format=$'#{?#{==:#{key_table},prefix},#{key_prefix} ,}#{key_string}\t#{key_note}'
  local private_server_socket="hypr-app-hints"
  local listing=""

  listing="$(tmux list-keys -N -F "${key_and_note_format}" 2>/dev/null || true)"
  if [[ -z "${listing}" && -f "${conf}" ]]; then
    listing="$(tmux -L "${private_server_socket}" -f "${conf}" start-server \; \
      list-keys -N -F "${key_and_note_format}" \; kill-server 2>/dev/null || true)"
  fi
  [[ -n "${listing}" ]] || return 1
  printf '%s\n' "${listing}"
}

# kitty has no resolved-keymap dump in this build, so read the config layers
list_kitty_bindings() {
  local conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
  local -a confs=("${conf_dir}"/*.conf)

  [[ -e "${confs[0]}" ]] || return 1
  awk '
    /^[ \t]*map[ \t]/ {
      line = $0
      sub(/^[ \t]*map[ \t]+/, "", line)
      cond = ""
      while (line ~ /^--/) {
        option = line
        sub(/[ \t].*/, "", option)
        sub(/^[^ \t]+[ \t]+/, "", line)
        if (option ~ /=/) {
          value = option
          sub(/^[^=]*=/, "", value)
          sub(/=.*/, "", option)
        } else {
          value = line
          sub(/[ \t].*/, "", value)
          sub(/^[^ \t]+[ \t]+/, "", line)
        }
        if (option == "--when-focus-on") cond = " (" value ")"
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
  kitty) binds="$(list_kitty_bindings || true)" ;;
  tmux) binds="$(list_tmux_bindings || true)" ;;
  *) printf 'usage: %s <kitty|tmux>\n' "$(basename "$0")" >&2; exit 1 ;;
esac

if [[ -z "${binds}" ]]; then
  dunstify -t "${NOTIFY_LONG_MS}" -i dialog-error "Keybind hints" "No ${app} bindings found."
  exit 0
fi

rows="$(awk -F '\t' '
  { keys[NR] = $1; actions[NR] = $2; if (length($1) > key_width) key_width = length($1) }
  END { for (row = 1; row <= NR; row++) printf "%-" key_width "s >   %s\n", keys[row], actions[row] }
' <<<"${binds}")"
font_scale="$(rofi_effective_font_scale "${ROFI_KEYBIND_HINT_SCALE:-}")"
font_name="$(rofi_effective_font_name "${ROFI_KEYBIND_HINT_FONT:-${ROFI_FONT:-}}")"

# same geometry and overrides as keybinds_hint, so the cheatsheets match
printf '%s\n' "${rows}" | rofi_with_background_theme -dmenu -i -no-custom -no-show-icons -p " ${app}" \
  -theme "$(rofi_resolve_theme "${ROFI_KEYBIND_HINT_STYLE:-clipboard}")" \
  -theme-str "entry { placeholder: \"  Keybindings\"; }" \
  -theme-str "$(rofi_font_override "${font_name}" "${font_scale}")" \
  -theme-str "$(rofi_icon_theme_override)" \
  -theme-str "$(rofi_standard_window_theme listview same)" \
  -theme-str "$(rofi_cheatsheet_layout_override "$(wc -l <<<"${rows}")" "${font_name}" "${font_scale}")" \
  >/dev/null
