#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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
  local defaults_file=""

  [[ -n "${var_name}" && -r "${file}" ]] || return 1

  if command -v hyq &>/dev/null; then
    value="$(hyq --query "\$${var_name}" "${file}" 2>/dev/null || true)"
    [[ -n "${value}" ]] && printf '%s\n' "${value}" && return 0
  fi

  value="$(get_hypr_conf_from_file "${file}" "\$${var_name}")"
  if [[ -n "${value}" ]] && [[ "${value}" != \$* ]]; then
    printf '%s\n' "${value}"
    return 0
  fi

  defaults_file="$(hypr_variables_file)"
  if [[ -f "${defaults_file}" ]]; then
    get_hypr_conf_from_file "${defaults_file}" "\$default.${var_name}"
  fi
}

paste_string() {
  local class=""
  local arg=""
  local ignored_class=""
  local -a ignored_classes=(
    kitty
    foot
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

ini_write() {
  local config_file="${1}"
  local group="${2}"
  local key="${3}"
  local value="${4}"

  [[ -n "${config_file}" && -n "${group}" && -n "${key}" ]] || return 1

  if [[ ! -f "${config_file}" ]]; then
    mkdir -p "$(dirname "${config_file}")" || return 1
    : >"${config_file}" || return 1
  fi

  if command -v kwriteconfig6 >/dev/null 2>&1 &&
    kwriteconfig6 --file "${config_file}" --group "${group}" --key "${key}" "${value}" 2>/dev/null; then
    return 0
  fi

  ini_write_multi "${config_file}" "${group}" "${key}" "${value}"
}

# Reads group<TAB>key<TAB>value records; direct arguments serve ini_write's fallback.
# Direct batch calls bypass KConfig cascade and immutability handling.
ini_write_multi() {
  local config_file="${1}"
  local config_dir="" tmp_file="" records_file=/dev/stdin single=0
  local ini_group="${2:-}" ini_key="${3:-}" ini_value="${4:-}"

  [[ -z "${config_file}" ]] && return 1
  config_dir="${config_file%/*}"
  [[ "${config_dir}" != "${config_file}" ]] || config_dir=.

  if (($# > 1)); then
    [[ -n "${ini_group}" && -n "${ini_key}" ]] || return 1
    records_file=/dev/null
    single=1
  fi

  if [[ ! -f "${config_file}" ]]; then
    mkdir -p "${config_dir}" || return 1
    : >"${config_file}" || return 1
  fi

  tmp_file="$(mktemp "${config_dir}/.ini-write.XXXXXX")" || return 1

  INI_SINGLE="${single}" INI_GROUP="${ini_group}" INI_KEY="${ini_key}" INI_VALUE="${ini_value}" awk -F'\t' '
    function queue(sec, key, value) {
      if (!((sec, key) in pending)) keys[sec, ++key_count[sec]] = key
      if (!(sec in group_seen)) group_order[++group_total] = sec
      group_seen[sec] = 1
      pending[sec, key] = value
    }
    function flush_group(sec,   i, k) {
      for (i = 1; i <= key_count[sec]; i++) {
        k = keys[sec, i]
        if (!((sec, k) in written)) {
          print k "=" pending[sec, k]
          written[sec, k] = 1
        }
      }
    }
    BEGIN {
      if (ENVIRON["INI_SINGLE"] == "1")
        queue(ENVIRON["INI_GROUP"], ENVIRON["INI_KEY"], ENVIRON["INI_VALUE"])
    }
    FILENAME == ARGV[1] {
      if (NF < 3 || $1 == "" || $2 == "") next
      value = $3
      for (field = 4; field <= NF; field++) value = value FS $field
      queue($1, $2, value)
      next
    }
    /^[[:space:]]*\[/ {
      if (in_group != "") {
        flush_group(in_group)
      }

      section = $0
      sub(/^[[:space:]]*\[/, "", section)
      sub(/\][[:space:]]*$/, "", section)
      in_group = (section in group_seen) ? section : ""
      if (in_group != "") {
        group_found[in_group] = 1
      }

      lines++
      print
      next
    }
    {
      if (in_group != "") {
        lhs = $0
        sub(/=.*$/, "", lhs)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
        if ((in_group, lhs) in pending) {
          if (!((in_group, lhs) in written)) {
            print lhs "=" pending[in_group, lhs]
            written[in_group, lhs] = 1
          }
          lines++
          next
        }
      }

      lines++
      print
    }
    END {
      if (in_group != "") {
        flush_group(in_group)
      }

      for (i = 1; i <= group_total; i++) {
        if (!(group_order[i] in group_found)) {
          if (lines > 0) {
            print ""
          }
          print "[" group_order[i] "]"
          flush_group(group_order[i])
          lines++
        }
      }
    }
  ' "${records_file}" "${config_file}" >"${tmp_file}" || {
    rm -f "${tmp_file}"
    return 1
  }

  mv -f "${tmp_file}" "${config_file}" || {
    rm -f "${tmp_file}"
    return 1
  }
}
