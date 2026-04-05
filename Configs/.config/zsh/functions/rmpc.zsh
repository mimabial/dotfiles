function rmpc() {
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local config_path="${config_home}/rmpc/config.ron"
  local theme_dir="${config_home}/rmpc/themes"
  local backup_path="${config_path}.bak"
  local rows=""
  local cols=""
  local size=""

  if [[ -f "$backup_path" ]] && [[ -f "$config_path" ]] && [[ "$config_path" -nt "$backup_path" ]]; then
    rm -f "$backup_path"
  fi

  size="$(stty size </dev/tty 2>/dev/null)"
  if [[ -n "$size" ]]; then
    read -r rows cols <<< "$size"
  fi
  rows="${rows:-${LINES:-24}}"
  cols="${cols:-${COLUMNS:-80}}"

  local base_theme="pywal16"
  local small_theme="pywal16-small"
  local big_theme="pywal16-big"

  local target_theme=""
  if (( cols < 90 && rows < 30 )); then
    target_theme="$small_theme"
  elif (( cols < 90 || rows < 30 )); then
    target_theme="$base_theme"
  else
    target_theme="$big_theme"
  fi

  local target_theme_path="${theme_dir}/${target_theme}.ron"

  if [[ -f "$config_path" ]] && [[ -f "$target_theme_path" ]]; then
    local current_theme=""
    current_theme="$(grep -oP 'theme:\s*Some\("\K[^"]+' "$config_path" 2>/dev/null || true)"
    if [[ "$current_theme" != "$target_theme" ]]; then
      "${config_home}/rmpc/lib/apply_theme" "$target_theme" "$target_theme_path" || true
      rm -f "$backup_path"
    fi
  fi

  command rmpc "$@"
}
