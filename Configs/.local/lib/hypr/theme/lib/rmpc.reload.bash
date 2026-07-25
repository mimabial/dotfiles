#!/usr/bin/env bash
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
config="${config_home}/rmpc/config.ron"

[[ -f "${config}" ]] || exit 0

theme_name="$(sed -nE 's/.*theme:[[:space:]]*Some\("([^"]+)".*/\1/p; T; q' "${config}" 2>/dev/null)"
case "${theme_name}" in
  pywal16 | pywal16-small | pywal16-big) ;;
  *) exit 0 ;;
esac

theme_path="${config_home}/rmpc/themes/${theme_name}.ron"
[[ -f "${theme_path}" ]] || exit 0

apply_theme="${config_home}/rmpc/lib/apply_theme"
if [[ -r "${apply_theme}" ]]; then
  bash "${apply_theme}" --prepare
  RMPC_APPLY_FORCE=1 bash "${apply_theme}" "${theme_name}" "${theme_path}"
fi
