#!/bin/bash

# Detect AUR helper (prefer yay, fallback to paru)
if command -v yay &>/dev/null; then
  AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
  AUR_HELPER="paru"
else
  AUR_HELPER="pacman"
fi

fzf_args=(
  --multi
  --preview "$AUR_HELPER -Qi {1}"
  --preview-label='alt-p: toggle description, alt-j/k: scroll, tab: multi-select'
  --preview-label-pos='bottom'
  --preview-window 'down:65%:wrap'
  --bind 'alt-p:toggle-preview'
  --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
  --bind 'alt-k:preview-up,alt-j:preview-down'
  --color 'pointer:red,marker:red'
)

pkg_names=$($AUR_HELPER -Qqe | fzf "${fzf_args[@]}")

if [[ -n "$pkg_names" ]]; then
  # Convert newline-separated selections to space-separated
  echo "$pkg_names" | tr '\n' ' ' | xargs sudo pacman -Rns --noconfirm
  hyprshell util/show-done.sh
fi
