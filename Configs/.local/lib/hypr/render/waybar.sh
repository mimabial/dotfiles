#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init waybar colors.css

variant="$(jq -r '.background // "dark"' "${PALETTE}")"
[[ "${variant}" =~ ^(dark|light)$ ]] || variant="dark"
templates_dir="${XDG_CONFIG_HOME:-$HOME/.config}/wal/templates"
template_variant="${templates_dir}/colors-waybar.${variant}.css"
template_default="${templates_dir}/colors-waybar.css"
template=""
[[ -f "${template_variant}" ]] && template="${template_variant}"
[[ -z "${template}" && -f "${template_default}" ]] && template="${template_default}"

hash="$(
  {
    render_input_hash
    printf 'variant:%s\n' "${variant}"
    [[ -n "${template}" ]] && cat "${template}"
  } | { xxh64sum 2>/dev/null || md5sum; } | awk '{print $1}'
)"
render_should_skip "${hash}" && exit 0

tmp="$(render_temp)"
trap 'rm -f "${tmp}"' EXIT

if [[ -n "${PACK_OVERRIDE}" ]]; then
  render_emit_pack_override "${tmp}"
else
  mapfile -t C < <(jq -r '.bg, .fg, (.colors[])' "${PALETTE}")
  bg="${C[0]}" fg="${C[1]}"
  c=("${C[@]:2}")
  declare -A vars=(
    [background]="${bg}"
    [foreground]="${fg}"
  )
  for i in "${!c[@]}"; do
    vars["color${i}"]="${c[$i]}"
  done

  if [[ -f "${template}" ]]; then
    content="$(<"${template}")"
  else
    content=$'/* Waybar colors generated from active palette */\n\n'
    content+=$'@define-color bg {background};\n'
    content+=$'@define-color fg {color7};\n'
    content+=$'@define-color br {color5};\n\n'
    content+=$'@define-color alt_bg {color6};\n'
    content+=$'@define-color alt_fg {color3};\n'
    content+=$'@define-color alt_br {color11};\n\n'
    content+=$'@define-color fg_selected {color4};\n\n'
    content+=$'@define-color act_bg {color8};\n'
    content+=$'@define-color act_fg {color7};\n'
    content+=$'@define-color act_br {color13};\n\n'
    content+=$'@define-color hvr_bg {background};\n'
    content+=$'@define-color hvr_fg {foreground};\n'
    content+=$'@define-color hvr_br {color12};\n\n'
    content+=$'@define-color c0 {color0};\n@define-color c1 {color1};\n@define-color c2 {color2};\n@define-color c3 {color3};\n'
    content+=$'@define-color c4 {color4};\n@define-color c5 {color5};\n@define-color c6 {color6};\n@define-color c7 {color7};\n'
    content+=$'@define-color c8 {color8};\n@define-color c9 {color9};\n@define-color c10 {color10};\n@define-color c11 {color11};\n'
    content+=$'@define-color c12 {color12};\n@define-color c13 {color13};\n@define-color c14 {color14};\n@define-color c15 {color15};\n\n'
    content+=$'@define-color accent {color12};\n@define-color info {color6};\n@define-color warning {color3};\n@define-color error {color1};\n@define-color success {color2};\n'
  fi

  for key in "${!vars[@]}"; do
    content="${content//\{${key}\}/${vars[$key]}}"
  done

  {
    printf '%s\n' "${content}"
    printf '\n/* Compatibility aliases for styles that use generic pywal names. */\n'
    printf '@define-color background %s;\n' "${bg}"
    printf '@define-color foreground %s;\n' "${fg}"
    for i in "${!c[@]}"; do
      printf '@define-color color%s %s;\n' "$i" "${c[$i]}"
    done
  } > "${tmp}"
fi

render_commit "${tmp}" "${hash}"
trap - EXIT
