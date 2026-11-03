#!/usr/bin/env bash

declare -F hypr_config_value_from_layers_into >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/config-layers.bash" || return 1

font_sync_ensure_runtime() {
  if declare -F hypr_runtime_require >/dev/null 2>&1; then
    return 0
  fi

  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || return 1
}

font_sync_resolve_font_value() {
  local kind="$1"
  local mono_font=""
  local bar_font=""
  local bar_icon_font=""
  local menu_font=""
  local terminal_font=""

  case "${kind}" in
    mono)
      hypr_config_value_from_layers_into mono_font MONOSPACE_FONT 2>/dev/null || true
      printf '%s\n' "${mono_font:-monospace}"
      ;;
    bar)
      hypr_config_value_from_layers_into bar_font BAR_FONT 2>/dev/null || true
      printf '%s\n' "${bar_font:-monospace}"
      ;;
    bar-icon)
      hypr_config_value_from_layers_into bar_icon_font BAR_ICON_FONT 2>/dev/null || true
      printf '%s\n' "${bar_icon_font:-CaskaydiaCove Nerd Font}"
      ;;
    menu)
      hypr_config_value_from_layers_into menu_font MENU_FONT 2>/dev/null || true
      printf '%s\n' "${menu_font:-monospace}"
      ;;
    terminal)
      # Packs that predate $TERMINAL_FONT still carry $MONOSPACE_FONT.
      hypr_config_value_from_layers_into terminal_font TERMINAL_FONT 2>/dev/null || true
      [[ -n "${terminal_font}" ]] || hypr_config_value_from_layers_into terminal_font MONOSPACE_FONT 2>/dev/null || true
      printf '%s\n' "${terminal_font:-monospace}"
      ;;
    *) return 1 ;;
  esac
}

font_sync_ensure_sed_escape() {
  declare -F sed_escape_replacement >/dev/null 2>&1 && return 0
  font_sync_ensure_runtime || return 1
  hypr_runtime_require system
}

font_sync_apply_kitty_family() {
  local font="$1"
  local kitty_conf="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
  local escaped=""

  [[ -n "${font}" ]] || return 1
  [[ -f "${kitty_conf}" ]] || return 1
  font_sync_ensure_sed_escape || return 1
  escaped="$(sed_escape_replacement "${font}")"
  sed -i "s|^font_family .*|font_family ${escaped}|g" "${kitty_conf}"
}

font_sync_apply_alacritty_family() {
  local font="$1"
  local alacritty_conf="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
  local quoted="" escaped="" desired=""

  [[ -n "${font}" && -f "${alacritty_conf}" ]] || return 1
  quoted="$(jq -Rn --arg value "${font}" '$value')" || return 1
  desired="normal = { family = ${quoted} }"
  grep -Fxq -- "${desired}" "${alacritty_conf}" && return 0
  font_sync_ensure_sed_escape || return 1
  escaped="$(sed_escape_replacement "${quoted}")"
  sed -i "s|^normal = { family = .* }$|normal = { family = ${escaped} }|" "${alacritty_conf}"
}
