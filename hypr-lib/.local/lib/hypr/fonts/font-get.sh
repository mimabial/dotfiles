#!/usr/bin/env bash

set -euo pipefail

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
fi

kind="${1:-}"

usage() {
  cat <<'EOF'
Usage: hyprshell fonts/font-get.sh <kind>

Kinds:
  mono   -> $MONOSPACE_FONT
  bar    -> $BAR_FONT (fallback to mono)
  menu   -> $MENU_FONT (fallback to mono)
EOF
}

[[ -z "${kind}" || "${kind}" == "-h" || "${kind}" == "--help" ]] && usage && exit 0

hypr_config_dir="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}"
userfonts_file="${hypr_config_dir}/userfonts.conf"
variables_file="${hypr_config_dir}/variables.conf"

get_var_from_file() {
  local file_path="$1"
  local var_name="$2"
  [[ -f "${file_path}" ]] || return 1
  awk -F= -v key="$var_name" '
    $0 ~ "^\\$" key "=" {
      sub("^\\$" key "=", "", $0);
      print $0;
      exit 0
    }
  ' "${file_path}"
}

get_var() {
  local var_name="$1"

  # Prefer persistent user overrides, fallback to variables.conf.
  local v
  v="$(get_var_from_file "${userfonts_file}" "${var_name}" || true)"
  [[ -n "${v}" ]] && { echo "${v}"; return 0; }
  get_var_from_file "${variables_file}" "${var_name}"
}

mono_font="$(get_var "MONOSPACE_FONT" || true)"
bar_font="$(get_var "BAR_FONT" || true)"
menu_font="$(get_var "MENU_FONT" || true)"

[[ -n "${mono_font}" ]] || mono_font="monospace"
[[ -n "${bar_font}" ]] || bar_font="${mono_font}"
[[ -n "${menu_font}" ]] || menu_font="${mono_font}"

case "${kind}" in
  mono) echo "${mono_font}" ;;
  bar) echo "${bar_font}" ;;
  menu) echo "${menu_font}" ;;
  *)
    echo "Unknown kind: ${kind}" >&2
    usage >&2
    exit 2
    ;;
esac
