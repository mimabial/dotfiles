#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# color.targets.sh - Materialize theme target files and wallpaper-mode cleanup

active_theme_metadata_file() {
  printf '%s\n' "${HYPR_THEME_METADATA_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.meta}"
}

hypr_layered_value() {
  local key="$1"
  local config_file value=""

  for config_file in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/userfonts.lua" \
    "$(active_theme_metadata_file)" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/hypr/variables.meta"
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
        $0 ~ "^[[:space:]]*vars\\.set\\(\\\"" key "\\\"," {
          value = $0
          sub(/^[^,]*,[[:space:]]*\"/, "", value)
          sub(/\"\).*/, "", value)
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
    if declare -F theme_phase_d_promote_file >/dev/null 2>&1; then
      theme_phase_d_promote_file "${source_file}" "${target_file}" || return 1
    else
      mv -f "${source_file}" "${target_file}"
    fi
    changed=1
  fi

  if [[ -n "${changed_var}" ]]; then
    printf -v "${changed_var}" '%s' "${changed}"
  fi
}

theme_target_filter_allows() {
  local theme_basename="$1"
  local filter="${HYPR_THEME_FILE_BASENAMES:-}"

  [[ -n "${filter}" ]] || return 0
  case " ${filter} " in
    *" ${theme_basename} "*) return 0 ;;
    *) return 1 ;;
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

  local theme_file first_line theme_basename target_path
  local new_content new_hash old_hash
  local tmp_target=""

  while IFS= read -r theme_file; do
    [ ! -f "${theme_file}" ] && continue
    theme_basename="$(basename "${theme_file}")"
    case "${theme_basename}" in
      hypr.theme|kitty.theme|rofi.theme|waybar.theme|alacritty.theme|tmux.theme|dunst.theme) continue ;;
    esac
    [[ "${theme_file}" =~ /kvantum/.*\.theme$ ]] && continue

    first_line=$(head -1 "${theme_file}")
    theme_target_filter_allows "${theme_basename}" || continue
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
      tmp_target="$(mktemp "$(dirname "${target_path}")/.theme-target.XXXXXX")" || continue
      printf '%s\n' "${new_content}" >"${tmp_target}"
      rewrite_if_changed "${tmp_target}" "${target_path}"
      print_log -sec "theme" -stat "wrote" "${target_path}"
    else
      [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -sec "theme" -stat "skip" "${target_path} (unchanged)"
    fi

  done < <(find "${HYPR_THEME_DIR}" -type f -name "*.theme" 2>/dev/null)
}
