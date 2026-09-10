#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Callers may source runtime/init.bash first, but these helpers also lazily
# load it when they need layered config access.

font_sync_ensure_runtime() {
  if declare -F hypr_config_value_from_layers >/dev/null 2>&1; then
    return 0
  fi

  local lib_dir="${LIB_DIR:-$HOME/.local/lib}"
  # shellcheck source=/dev/null
  source "${lib_dir}/hypr/runtime/init.bash" || return 1
}

font_sync_resolve_font_value() {
  local kind="$1"
  local mono_font=""
  local bar_font=""
  local bar_icon_font=""
  local menu_font=""
  local terminal_font=""

  font_sync_ensure_runtime || return 1

  case "${kind}" in
    mono)
      mono_font="$(hypr_config_value_from_layers "MONOSPACE_FONT" 2>/dev/null || true)"
      printf '%s\n' "${mono_font:-monospace}"
      ;;
    bar)
      bar_font="$(hypr_config_value_from_layers "BAR_FONT" 2>/dev/null || true)"
      printf '%s\n' "${bar_font:-monospace}"
      ;;
    bar-icon)
      bar_icon_font="$(hypr_config_value_from_layers "BAR_ICON_FONT" 2>/dev/null || true)"
      printf '%s\n' "${bar_icon_font:-CaskaydiaCove Nerd Font}"
      ;;
    menu)
      menu_font="$(hypr_config_value_from_layers "MENU_FONT" 2>/dev/null || true)"
      printf '%s\n' "${menu_font:-monospace}"
      ;;
    terminal)
      # Packs that predate $TERMINAL_FONT still carry $MONOSPACE_FONT.
      terminal_font="$(hypr_config_value_from_layers "TERMINAL_FONT" 2>/dev/null || true)"
      [[ -n "${terminal_font}" ]] || terminal_font="$(hypr_config_value_from_layers "MONOSPACE_FONT" 2>/dev/null || true)"
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
  local escaped=""

  [[ -n "${font}" ]] || return 1
  [[ -f "${alacritty_conf}" ]] || return 1
  font_sync_ensure_sed_escape || return 1
  escaped="$(sed_escape_replacement "${font}")"
  sed -i "s|family = \".*\"|family = \"${escaped}\"|g" "${alacritty_conf}"
}
