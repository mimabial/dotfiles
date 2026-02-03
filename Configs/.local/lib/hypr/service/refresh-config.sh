#!/usr/bin/env bash

set -euo pipefail

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
fi

rel_path="${1:-}"
if [[ -z "${rel_path}" || "${rel_path}" == "-h" || "${rel_path}" == "--help" ]]; then
  echo "Usage: hyprshell service/refresh-config.sh <relative-path-under-config>" >&2
  echo "Example: hyprshell service/refresh-config.sh waybar/config.jsonc" >&2
  exit 2
fi

target="${XDG_CONFIG_HOME:-$HOME/.config}/${rel_path}"

# Prefer local config templates if present.
source_candidates=(
  "${HOME}/.local/share/hypr/defaults/.config/${rel_path}"
)

src=""
for candidate in "${source_candidates[@]}"; do
  if [[ -f "${candidate}" ]]; then
    src="${candidate}"
    break
  fi
done

if [[ -z "${src}" ]]; then
  echo "No template found for: ${rel_path}" >&2
  echo "Tried:" >&2
  printf "  - %s\n" "${source_candidates[@]}" >&2
  exit 1
fi

mkdir -p "$(dirname "${target}")"

if [[ -f "${target}" ]]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  cp -f "${target}" "${target}.bak.${ts}"
fi

cp -f "${src}" "${target}"
echo "Refreshed: ${target}"
