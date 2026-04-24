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
  local defer_live_reload=0

  [[ "${HYPR_THEME_BATCH_RELOADS:-0}" -eq 1 ]] && defer_live_reload=1

  case "${hook_name}" in
    kitty)
      (( defer_live_reload )) || pkill -SIGUSR1 kitty >/dev/null 2>&1 || true
      ;;
    dunst)
      if [[ -x "${LIB_DIR}/hypr/wal/wal.dunst.sh" ]]; then
        if (( defer_live_reload )); then
          "${LIB_DIR}/hypr/wal/wal.dunst.sh" --write-only >/dev/null 2>&1 || true
        else
          "${LIB_DIR}/hypr/wal/wal.dunst.sh" >/dev/null 2>&1 || true
        fi
      elif command -v hyprshell &>/dev/null; then
        if (( defer_live_reload )); then
          hyprshell wal/wal.dunst.sh --write-only >/dev/null 2>&1 || true
        else
          hyprshell wal/wal.dunst.sh >/dev/null 2>&1 || true
        fi
      fi
      ;;
    tmux)
      if (( ! defer_live_reload )) && command -v tmux &>/dev/null && tmux list-sessions &>/dev/null; then
        tmux source-file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

active_theme_metadata_file() {
  printf '%s\n' "${HYPR_THEME_METADATA_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf}"
}

hypr_layered_value() {
  local key="$1"
  local config_file value=""

  for config_file in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/userfonts.conf" \
    "$(active_theme_metadata_file)" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/hypr/variables.conf"
  do
    [[ -r "${config_file}" ]] || continue
    value="$(
      awk -F= -v key="${key}" '
        $0 ~ "^\\$" key "[[:space:]]*=" {
          value = substr($0, index($0, "=") + 1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      ' "${config_file}"
    )"
    [[ -n "${value}" ]] && {
      printf '%s\n' "${value}"
      return 0
    }
  done

  return 1
}

rewrite_if_changed() {
  local source_file="$1"
  local target_file="$2"
  local changed_var="${3:-}"
  local changed=0

  if [[ -f "${target_file}" ]] && cmp -s "${source_file}" "${target_file}"; then
    rm -f "${source_file}"
  else
    mv -f "${source_file}" "${target_file}"
    changed=1
  fi

  if [[ -n "${changed_var}" ]]; then
    printf -v "${changed_var}" '%s' "${changed}"
  fi
}

resolve_theme_target_path() {
  local theme_basename="$1"
  local target_path="$2"

  case "${theme_basename}" in
    rofi.theme) printf '%s\n' "${HOME}/.config/rofi/theme.generated.rasi" ;;
    waybar.theme) printf '%s\n' "${HOME}/.config/waybar/theme.generated.css" ;;
    kitty.theme) printf '%s\n' "${HOME}/.config/kitty/theme.generated.conf" ;;
    alacritty.theme) printf '%s\n' "${HOME}/.config/alacritty/theme.generated.toml" ;;
    tmux.theme) printf '%s\n' "${HOME}/.config/tmux/theme.generated.conf" ;;
    dunst.theme) printf '%s\n' "${HOME}/.config/dunst/theme.generated.conf" ;;
    *) printf '%s\n' "${target_path}" ;;
  esac
}

apply_kitty_theme_font_override() {
  local target_file="$1"
  local changed_var="${2:-}"
  local theme_font=""
  local tmp_file
  local changed=0

  theme_font="$(hypr_layered_value "TERMINAL_FONT" 2>/dev/null || true)"
  tmp_file="$(mktemp "$(dirname "${target_file}")/.kitty-theme-font.XXXXXX")" || return 1

  awk '
    /^[[:space:]]*font_family[[:space:]]+/ { next }
    { print }
  ' "${target_file}" > "${tmp_file}"

  if [[ -n "${theme_font}" ]]; then
    printf '\nfont_family     %s\n' "${theme_font}" >> "${tmp_file}"
  fi

  rewrite_if_changed "${tmp_file}" "${target_file}" changed || return 1
  if [[ -n "${changed_var}" ]]; then
    printf -v "${changed_var}" '%s' "${changed}"
  fi
}

apply_alacritty_theme_font_override() {
  local target_file="$1"
  local changed_var="${2:-}"
  local theme_font=""
  local tmp_file
  local changed=0

  theme_font="$(hypr_layered_value "TERMINAL_FONT" 2>/dev/null || true)"
  tmp_file="$(mktemp "$(dirname "${target_file}")/.alacritty-theme-font.XXXXXX")" || return 1

  awk '
    /^\[font\.(normal|bold|italic|bold_italic)\][[:space:]]*$/ { skip = 1; next }
    skip && /^\[/ { skip = 0 }
    !skip { print }
  ' "${target_file}" > "${tmp_file}"

  if [[ -n "${theme_font}" ]]; then
    cat >> "${tmp_file}" <<EOF

[font.normal]
family = "${theme_font}"
style = "Regular"

[font.bold]
family = "${theme_font}"
style = "Bold"

[font.italic]
family = "${theme_font}"
style = "Italic"

[font.bold_italic]
family = "${theme_font}"
style = "Bold Italic"
EOF
  fi

  rewrite_if_changed "${tmp_file}" "${target_file}" changed || return 1
  if [[ -n "${changed_var}" ]]; then
    printf -v "${changed_var}" '%s' "${changed}"
  fi
}

apply_terminal_theme_font_override() {
  local theme_basename="$1"
  local target_file="$2"
  local changed_var="${3:-}"

  case "${theme_basename}" in
    kitty.theme)
      apply_kitty_theme_font_override "${target_file}" "${changed_var}"
      ;;
    alacritty.theme)
      apply_alacritty_theme_font_override "${target_file}" "${changed_var}"
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

  if [[ -f "${HYPR_THEME_DIR}/tmux.theme" ]]; then
    clear_theme_file "${HOME}/.config/tmux/colors.conf"
  fi

  local -A requested_hooks=()
  local theme_file first_line theme_basename target_path hook_name
  local new_content new_hash old_hash
  local tmp_target=""
  local target_content_changed=0
  local target_font_changed=0
  local target_changed=0

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

    target_path="$(resolve_theme_target_path "${theme_basename}" "${target_path}")"

    [ -z "${target_path}" ] && {
      print_log -sec "theme" -warn "skip" "no target path in $(basename "${theme_file}")"
      continue
    }

    mkdir -p "$(dirname "${target_path}")"
    target_content_changed=0
    target_font_changed=0
    target_changed=0

    new_content="$(sed '1d' "${theme_file}")"
    new_hash="$(echo "${new_content}" | md5sum | cut -d' ' -f1)"
    old_hash=""
    [ -f "${target_path}" ] && old_hash="$(md5sum "${target_path}" 2>/dev/null | cut -d' ' -f1)"

    if [ "${new_hash}" != "${old_hash}" ]; then
      tmp_target="$(mktemp "$(dirname "${target_path}")/.theme-target.XXXXXX")" || continue
      printf '%s\n' "${new_content}" >"${tmp_target}"
      rewrite_if_changed "${tmp_target}" "${target_path}" target_content_changed
      print_log -sec "theme" -stat "wrote" "${target_path}"
    else
      [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -sec "theme" -stat "skip" "${target_path} (unchanged)"
    fi

    apply_terminal_theme_font_override "${theme_basename}" "${target_path}" target_font_changed

    if (( target_content_changed || target_font_changed )); then
      target_changed=1
    fi

    if (( target_changed )) && hook_name="$(theme_post_apply_hook_name "${theme_basename}" 2>/dev/null)"; then
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

write_theme_stub_file() {
  local target="$1"
  local content="$2"
  local tmp_file=""

  if [[ -f "${target}" ]] && [[ "$(cat "${target}")" == "${content}" ]]; then
    return
  fi

  mkdir -p "$(dirname "${target}")" || return 1
  tmp_file="$(mktemp "$(dirname "${target}")/.theme-stub.XXXXXX")" || return 1
  printf '%s' "${content}" >"${tmp_file}"
  rewrite_if_changed "${tmp_file}" "${target}"
}

apply_wallpaper_mode_theme_fallbacks() {
  local defer_live_reload=0

  [[ "${HYPR_THEME_BATCH_RELOADS:-0}" -eq 1 ]] && defer_live_reload=1

  print_log -sec "theme" -stat "cleanup" "clearing theme files (wallpaper mode)"

  clear_theme_file "${HOME}/.config/waybar/theme.generated.css"
  clear_theme_file "${HOME}/.config/kitty/theme.generated.conf"
  write_theme_stub_file "${HOME}/.config/alacritty/theme.generated.toml" "# Empty theme file
"
  clear_theme_file "${HOME}/.config/dunst/theme.generated.conf"
  if (( defer_live_reload )); then
    bash "${LIB_DIR}/hypr/wal/wal.dunst.sh" --write-only >/dev/null 2>&1 || true
  else
    bash "${LIB_DIR}/hypr/wal/wal.dunst.sh" >/dev/null 2>&1 || true
  fi
  clear_theme_file "${HOME}/.config/rofi/theme.generated.rasi"
  clear_theme_file "${HOME}/.config/tmux/theme.generated.conf"

  if (( ! defer_live_reload )); then
    pkill -SIGUSR1 kitty 2>/dev/null || true
    tmux source-file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" 2>/dev/null || true
  fi
}
