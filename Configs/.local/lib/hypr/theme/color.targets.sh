#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# color.targets.sh - Materialize theme target files and fallback theme outputs

theme_post_apply_hook_name() {
  case "$1" in
    kitty.theme) printf '%s\n' "kitty" ;;
    dunst.theme) printf '%s\n' "dunst" ;;
    tmux.theme) printf '%s\n' "tmux" ;;
    *) return 1 ;;
  esac
}

run_theme_post_apply_hook() {
  local hook_name="$1"

  case "${hook_name}" in
    kitty)
      pkill -SIGUSR1 kitty >/dev/null 2>&1 || true
      ;;
    dunst)
      if [[ -x "${LIB_DIR}/hypr/wal/wal.dunst.sh" ]]; then
        "${LIB_DIR}/hypr/wal/wal.dunst.sh" >/dev/null 2>&1 || true
      elif command -v hyprshell &>/dev/null; then
        hyprshell wal/wal.dunst.sh >/dev/null 2>&1 || true
      fi
      ;;
    tmux)
      if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null; then
        tmux source-file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

process_theme_files() {
  [ -z "${HYPR_THEME_DIR}" ] && {
    print_log -sec "theme" -warn "skip" "HYPR_THEME_DIR not set"
    return 0
  }
  [ ! -d "${HYPR_THEME_DIR}" ] && {
    print_log -sec "theme" -warn "skip" "theme directory not found: ${HYPR_THEME_DIR}"
    return 0
  }

  print_log -sec "theme" -stat "processing" ".theme files from ${HYPR_THEME}"

  local -A requested_hooks=()
  local theme_file first_line theme_basename target_path hook_name
  local new_content new_hash old_hash

  while IFS= read -r theme_file; do
    [ ! -f "${theme_file}" ] && continue
    [ "$(basename "${theme_file}")" = "hypr.theme" ] && continue
    [[ "${theme_file}" =~ /kvantum/.*\.theme$ ]] && continue

    first_line=$(head -1 "${theme_file}")
    theme_basename="$(basename "${theme_file}")"
    target_path="${first_line%%|*}"
    target_path="$(echo "${target_path}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    target_path="${target_path//\$HOME/$HOME}"
    target_path="${target_path//\$XDG_CONFIG_HOME/${XDG_CONFIG_HOME:-$HOME/.config}}"
    target_path="${target_path//\$XDG_CACHE_HOME/${XDG_CACHE_HOME:-$HOME/.cache}}"
    target_path="${target_path//\$XDG_DATA_HOME/${XDG_DATA_HOME:-$HOME/.local/share}}"
    target_path="${target_path//\$USER/$USER}"

    [ -z "${target_path}" ] && {
      print_log -sec "theme" -warn "skip" "no target path in $(basename "${theme_file}")"
      continue
    }

    mkdir -p "$(dirname "${target_path}")"

    new_content="$(sed '1d' "${theme_file}")"
    new_hash="$(echo "${new_content}" | md5sum | cut -d' ' -f1)"
    old_hash=""
    [ -f "${target_path}" ] && old_hash="$(md5sum "${target_path}" 2>/dev/null | cut -d' ' -f1)"

    if [ "${new_hash}" != "${old_hash}" ]; then
      echo "${new_content}" >"${target_path}"
      print_log -sec "theme" -stat "wrote" "${target_path}"
    else
      [[ "${LOG_LEVEL}" == "debug" ]] && print_log -sec "theme" -stat "skip" "${target_path} (unchanged)"
    fi

    if hook_name="$(theme_post_apply_hook_name "${theme_basename}" 2>/dev/null)"; then
      requested_hooks["${hook_name}"]=1
    fi

  done < <(find "${HYPR_THEME_DIR}" -type f -name "*.theme" 2>/dev/null)

  for hook_name in dunst kitty tmux; do
    if [[ -n "${requested_hooks[${hook_name}]:-}" ]]; then
      print_log -sec "theme" -stat "hook" "${hook_name}"
      run_theme_post_apply_hook "${hook_name}"
    fi
  done
}

clear_theme_file() {
  local target="$1"
  if [[ ! -f "${target}" ]]; then
    : >"${target}"
    return
  fi
  if grep -q '[^[:space:]]' "${target}"; then
    : >"${target}"
  fi
}

apply_wallpaper_mode_theme_fallbacks() {
  print_log -sec "theme" -stat "cleanup" "clearing theme files (wallpaper mode)"

  clear_theme_file "${HOME}/.config/waybar/theme.css"
  : >"${HOME}/.config/kitty/theme.conf"
  echo "# Empty theme file" >"${HOME}/.config/alacritty/theme.toml"
  : >"${HOME}/.config/dunst/theme.conf"
  bash "${LIB_DIR}/hypr/wal/wal.dunst.sh" >/dev/null 2>&1 || true
  cat >"${HOME}/.config/rofi/theme.rasi" <<'EOF'
/* Wallpaper mode (auto/dark/light): use pywal16 colors */
@import "~/.config/rofi/colors.rasi"
* {
    separatorcolor:     transparent;
    border-color:       transparent;
}
EOF
  : >"${HOME}/.config/tmux/theme.conf"

  pkill -SIGUSR1 kitty 2>/dev/null || true
  tmux source-file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" 2>/dev/null || true
}
