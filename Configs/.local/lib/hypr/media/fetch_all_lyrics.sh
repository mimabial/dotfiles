#!/usr/bin/env bash
set -euo pipefail

# One Python process scans metadata, reuses provider clients and applies the
# short-lived miss cache across the complete library.
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LYRICS_FETCHER="$SCRIPT_DIR/fetch_album_lyrics.py"
LYRICS_RUNTIME_SH="$SCRIPT_DIR/lyrics_runtime.sh"

if [[ ! -f "$LYRICS_FETCHER" || ! -f "$LYRICS_RUNTIME_SH" ]]; then
  echo "Error: lyrics runtime is incomplete under $SCRIPT_DIR" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$LYRICS_RUNTIME_SH"
PYTHON_EXEC="$(resolve_lyrics_python || true)"
if [[ -z "$PYTHON_EXEC" ]]; then
  echo "Error: managed lyrics Python is unavailable; run 'hyprshell pyinit'" >&2
  exit 1
fi

exec "$PYTHON_EXEC" "$LYRICS_FETCHER" --recursive "$@"
