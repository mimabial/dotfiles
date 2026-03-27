#!/usr/bin/env bash

set -euo pipefail

source "$(command -v hyprshell)" || exit 1

kind="${1:-}"

usage() {
  cat <<'EOF'
Usage: hyprshell fonts/font-get.sh <kind>

Kinds:
  mono   -> $MONOSPACE_FONT (fallback to native monospace)
  bar    -> $BAR_FONT (fallback to $FONT, then native monospace)
  menu   -> $MENU_FONT (fallback to $FONT, then native monospace)
EOF
}

[[ -z "${kind}" || "${kind}" == "-h" || "${kind}" == "--help" ]] && usage && exit 0

hypr_config_dir="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}"
hypr_shared_dir="${HYPR_DATA_HOME:-$HOME/.local/share/hypr}"
active_theme_file="${hypr_config_dir}/themes/theme.conf"
userfonts_file="${hypr_config_dir}/userfonts.conf"
if [[ -f "${hypr_shared_dir}/variables.conf" ]]; then
  variables_file="${hypr_shared_dir}/variables.conf"
else
  variables_file="${hypr_config_dir}/variables.conf"
fi

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

get_active_font_var() {
  local var_name="$1"
  local value=""

  value="$(get_var_from_file "${active_theme_file}" "${var_name}" || true)"
  [[ -n "${value}" ]] && {
    printf '%s\n' "${value}"
    return 0
  }

  get_var "${var_name}"
}

general_font="$(get_active_font_var "FONT" || true)"
mono_font="$(get_active_font_var "MONOSPACE_FONT" || true)"
bar_font="$(get_active_font_var "BAR_FONT" || true)"
menu_font="$(get_active_font_var "MENU_FONT" || true)"

[[ -n "${mono_font}" ]] || mono_font="monospace"
[[ -n "${bar_font}" ]] || bar_font="${general_font}"
[[ -n "${menu_font}" ]] || menu_font="${general_font}"
[[ -n "${bar_font}" ]] || bar_font="monospace"
[[ -n "${menu_font}" ]] || menu_font="monospace"

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
