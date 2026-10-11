#!/usr/bin/env bash
install_pack_config_overrides() {
  local pack_dir="$1"
  [[ -z "${pack_dir}" ]] && {
    print_log -sec "theme" -warn "skip" "HYPR_THEME_DIR not set"
    return 0
  }
  [[ ! -d "${pack_dir}" ]] && {
    print_log -sec "theme" -warn "skip" "theme directory not found: ${pack_dir}"
    return 0
  }

  print_log -sec "theme" -stat "processing" ".theme files from ${pack_dir##*/}"

  local theme_file="" target_header="" theme_basename="" target_path=""
  local config_content="" staged_config=""

  while IFS= read -r -d '' theme_file; do
    theme_basename="${theme_file##*/}"
    case "${theme_basename}" in
      hypr.theme|kitty.theme|rofi.theme|quickshell.theme|alacritty.theme|tmux.theme|dunst.theme) continue ;;
    esac
    IFS= read -r target_header <"${theme_file}" || true
    target_path="${target_header%%|*}"
    target_path="${target_path#"${target_path%%[![:space:]]*}"}"
    target_path="${target_path%"${target_path##*[![:space:]]}"}"

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

    mkdir -p "${target_path%/*}" || return 1
    staged_config="$(mktemp "${target_path%/*}/.theme-target.XXXXXX")" || return 1
    config_content="$(sed '1d' "${theme_file}")" || { rm -f -- "${staged_config}"; return 1; }
    printf '%s\n' "${config_content}" >"${staged_config}"
    if [[ -f "${target_path}" ]] && cmp -s "${staged_config}" "${target_path}"; then
      rm -f -- "${staged_config}"
      [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -sec "theme" -stat "skip" "${target_path} (unchanged)"
    else
      mv -f -- "${staged_config}" "${target_path}" || return 1
      print_log -sec "theme" -stat "wrote" "${target_path}"
    fi

  done < <(find "${pack_dir}" -type f -name '*.theme' -print0 2>/dev/null)
  return 0
}
