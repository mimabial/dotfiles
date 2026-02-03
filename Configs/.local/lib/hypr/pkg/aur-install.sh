#!/bin/bash

# Detect AUR helper (prefer yay, fallback to paru)
if command -v yay &>/dev/null; then
  AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
  AUR_HELPER="paru"
else
  echo "No AUR helper found. Please install yay or paru."
  exit 1
fi

fzf_args=(
  --multi
  --preview "$AUR_HELPER -Sii {1}"
  --preview-label='alt-p: toggle description, alt-b/B: toggle PKGBUILD, alt-j/k: scroll, tab: multi-select'
  --preview-label-pos='bottom'
  --preview-window 'down:65%:wrap'
  --bind 'alt-p:toggle-preview'
  --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
  --bind 'alt-k:preview-up,alt-j:preview-down'
  --bind "alt-b:change-preview:$AUR_HELPER -Gp {1} | tail -n +5"
  --bind "alt-B:change-preview:$AUR_HELPER -Sii {1}"
  --color 'pointer:green,marker:green'
)

pkg_names=$($AUR_HELPER -Pc | fzf "${fzf_args[@]}")

if [[ -n "$pkg_names" ]]; then
  # Convert newline-separated selections to space-separated
  echo "$pkg_names" | tr '\n' ' ' | xargs $AUR_HELPER -S --noconfirm
  sudo updatedb
  hyprshell util/show-done.sh
fi
