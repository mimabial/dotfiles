#!/usr/bin/env bash

pacman_preferred_aur_helper() {
  if command -v yay >/dev/null 2>&1; then
    printf 'yay\n'
    return 0
  fi

  if command -v paru >/dev/null 2>&1; then
    printf 'paru\n'
    return 0
  fi

  return 1
}

pacman_build_fzf_args() {
  local out_name="$1"
  local preview_cmd="$2"
  local color_name="$3"
  local preview_label="${4:-alt-p: toggle description, alt-j/k: scroll, tab: multi-select}"
  local extra_bind_1="${5:-}"
  local extra_bind_2="${6:-}"
  local -n out_ref="${out_name}"

  out_ref=(
    --multi
    --preview "${preview_cmd}"
    --preview-label="${preview_label}"
    --preview-label-pos='bottom'
    --preview-window 'down:65%:wrap'
    --bind 'alt-p:toggle-preview'
    --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
    --bind 'alt-k:preview-up,alt-j:preview-down'
    --color "pointer:${color_name},marker:${color_name}"
  )

  [[ -n "${extra_bind_1}" ]] && out_ref+=(--bind "${extra_bind_1}")
  [[ -n "${extra_bind_2}" ]] && out_ref+=(--bind "${extra_bind_2}")
}

run_pacman_privileged() {
  local -a pacman_args=("$@")

  if [[ -t 0 && -t 1 ]] && command -v sudo >/dev/null 2>&1; then
    sudo pacman "${pacman_args[@]}"
    return $?
  fi

  if command -v pkexec >/dev/null 2>&1; then
    pkexec pacman "${pacman_args[@]}"
    return $?
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo pacman "${pacman_args[@]}"
    return $?
  fi

  echo "Neither pkexec nor sudo is available." >&2
  return 1
}
