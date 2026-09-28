#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
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

  local theme_file first_line theme_basename target_path
  local new_content new_hash old_hash
  local tmp_target=""

  while IFS= read -r theme_file; do
    [ ! -f "${theme_file}" ] && continue
    theme_basename="$(basename "${theme_file}")"
    case "${theme_basename}" in
      hypr.theme|kitty.theme|rofi.theme|quickshell.theme|alacritty.theme|tmux.theme|dunst.theme|wlogout.theme) continue ;;
    esac
    first_line=$(head -1 "${theme_file}")
    target_path="${first_line%%|*}"
    target_path="$(echo "${target_path}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    target_path="${target_path//\$HOME/$HOME}"
    target_path="${target_path//\$XDG_CONFIG_HOME/${XDG_CONFIG_HOME:-$HOME/.config}}"
    target_path="${target_path//\$XDG_CACHE_HOME/${XDG_CACHE_HOME:-$HOME/.cache}}"
    target_path="${target_path//\$XDG_DATA_HOME/${XDG_DATA_HOME:-$HOME/.local/share}}"
    target_path="${target_path//\$USER/$USER}"

    # A pack whose first line is prose rather than a target would otherwise be
    # written into the caller's cwd under that literal name.
    case "${target_path}" in
      /*) ;;
      *)
        print_log -sec "theme" -warn "skip" "no target path in ${theme_basename}"
        continue
        ;;
    esac

    mkdir -p "$(dirname "${target_path}")"
    new_content="$(sed '1d' "${theme_file}")"
    new_hash="$(echo "${new_content}" | md5sum | cut -d' ' -f1)"
    old_hash=""
    [ -f "${target_path}" ] && old_hash="$(md5sum "${target_path}" 2>/dev/null | cut -d' ' -f1)"

    if [ "${new_hash}" != "${old_hash}" ]; then
      tmp_target="$(mktemp "$(dirname "${target_path}")/.theme-target.XXXXXX")" || continue
      printf '%s\n' "${new_content}" >"${tmp_target}"
      rewrite_if_changed "${tmp_target}" "${target_path}"
      print_log -sec "theme" -stat "wrote" "${target_path}"
    else
      [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -sec "theme" -stat "skip" "${target_path} (unchanged)"
    fi

  done < <(find "${HYPR_THEME_DIR}" -type f -name "*.theme" 2>/dev/null)
}
