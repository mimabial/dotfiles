#!/usr/bin/env bash
# Remove broken symlinks under the given paths (defaults to $HOME).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: cleanup_broken_links.sh [options] [path ...]

Options:
  -n, --dry-run    List broken symlinks only (do not delete)
  -p, --prompt     Confirm before deleting each symlink
  -x, --exclude P  Exclude path P (repeatable). Matches P and P/*
  -h, --help       Show this help

Examples:
  cleanup_broken_links.sh
  cleanup_broken_links.sh -n ~/.config ~/.local
  cleanup_broken_links.sh -x ~/.cache -x ~/.local/share/flatpak
EOF
}

dry_run=0
prompt=0
excludes=()
paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) dry_run=1 ;;
    -p|--prompt) prompt=1 ;;
    -x|--exclude)
      shift
      [[ $# -eq 0 ]] && { echo "Missing exclude path" >&2; exit 1; }
      excludes+=("$1")
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *) paths+=("$1") ;;
  esac
  shift
done

if [[ $# -gt 0 ]]; then
  paths+=("$@")
fi

if [[ ${#paths[@]} -eq 0 ]]; then
  paths=("$HOME")
fi

for root in "${paths[@]}"; do
  if [[ ! -e "$root" ]]; then
    echo "Skip missing path: $root" >&2
    continue
  fi

  find_expr=(find "$root")
  if [[ ${#excludes[@]} -gt 0 ]]; then
    find_expr+=( \( )
    for ex in "${excludes[@]}"; do
      find_expr+=( -path "$ex" -o -path "$ex/*" -o )
    done
    unset 'find_expr[${#find_expr[@]}-1]'
    find_expr+=( \) -prune -o )
  fi
  find_expr+=( -xtype l -print )

  while IFS= read -r link; do
    target=$(readlink "$link" 2>/dev/null || true)
    if [[ $dry_run -eq 1 ]]; then
      echo "[dry-run] $link -> $target"
      continue
    fi
    if [[ $prompt -eq 1 ]]; then
      read -r -p "Remove $link -> $target ? [y/N] " ans
      [[ "$ans" != [Yy]* ]] && continue
    fi
    rm -f -- "$link"
    echo "Removed $link -> $target"
  done < <("${find_expr[@]}")
done
