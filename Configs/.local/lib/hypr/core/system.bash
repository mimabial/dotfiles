#!/usr/bin/env bash

pkg_installed() {
  local package="${1:-}"

  [[ -n "${package}" ]] || return 1
  command -v "${package}" &>/dev/null && return 0
  command -v flatpak &>/dev/null && flatpak info "${package}" &>/dev/null && return 0
  hyprshell pm query "${package}" &>/dev/null
}

sed_escape_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s' "${value}"
}

get_aur_helper() {
  local helper=""

  for helper in yay paru; do
    command -v "${helper}" >/dev/null 2>&1 || continue
    printf '%s\n' "${helper}"
    return 0
  done
  return 1
}

get_hypr_conf_from_file() {
  local file="$1"
  local key="$2"

  [[ -r "${file}" ]] || return 1

  awk -F'=' -v key="${key}" '
    /^[[:space:]]*#/ { next }
    {
      lhs = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
      if (lhs == key) {
        sub(/^[^=]*=/, "", $0)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    }
  ' "${file}"
}

get_hypr_conf() {
  local var_name="${1}"
  local file="${2:-"$HYPR_THEME_DIR/hypr.theme"}"
  local value=""

  [[ -n "${var_name}" && -r "${file}" ]] || return 1

  if command -v hyq &>/dev/null; then
    value="$(hyq --query "\$${var_name}" "${file}" 2>/dev/null || true)"
    [[ -n "${value}" ]] && printf '%s\n' "${value}" && return 0
  fi

  value="$(get_hypr_conf_from_file "${file}" "\$${var_name}")"
  if [[ -n "${value}" ]] && [[ "${value}" != \$* ]]; then
    printf '%s\n' "${value}"
  fi
}

paste_string() {
  local class=""
  local arg=""
  local ignored_class=""
  local -a ignored_classes=(
    kitty
    Alacritty
  )

  [[ -t 1 ]] && return 0

  for arg in "$@"; do
    case "${arg}" in
      --ignore=*)
        ignored_class="${arg#--ignore=}"
        [[ -n "${ignored_class}" ]] && ignored_classes+=("${ignored_class}")
        ;;
    esac
  done

  class="$(hyprctl -j activewindow | jq -r '.initialClass // empty')"
  for ignored_class in "${ignored_classes[@]}"; do
    [[ "${class}" == "${ignored_class}" ]] && return 0
  done

  if command -v wtype >/dev/null; then
    hypr_lua_dispatch 'hl.dsp.exec_cmd("wtype -M ctrl V -m ctrl")' >/dev/null
  elif command -v hyprctl >/dev/null; then
    hypr_lua_dispatch 'hl.dsp.send_shortcut({mods="CTRL", key="V", window="activewindow"})' >/dev/null
  fi
}

# Batch records bypass KConfig cascade and immutability handling.
ini_write_records() {
  local config_file="${1}"
  local config_dir="" tmp_file=""

  [[ -z "${config_file}" ]] && return 1
  config_dir="${config_file%/*}"
  [[ "${config_dir}" != "${config_file}" ]] || config_dir=.

  if [[ ! -f "${config_file}" ]]; then
    mkdir -p "${config_dir}" || return 1
    : >"${config_file}" || return 1
  fi

  tmp_file="$(mktemp "${config_dir}/.ini-write.XXXXXX")" || return 1
  if awk -f "${BASH_SOURCE[0]%/*}/ini-merge.awk" /dev/stdin "${config_file}" >"${tmp_file}" \
    && mv -f "${tmp_file}" "${config_file}"; then
    return 0
  fi
  rm -f "${tmp_file}"
  return 1
}
