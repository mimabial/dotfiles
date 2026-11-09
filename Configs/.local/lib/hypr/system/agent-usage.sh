#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/agent-usage [--write] [--force] [agent...]

Collect AI coding agent usage and limits as JSON.

  (no args)   print a JSON array of records for every agent that reports usage
  --write     refresh the cache the bar reads instead of printing
  --force     rescan local usage now, for a person who asked rather than for a
              periodic refresh. The limits probe keeps its own short window,
              which is what stops repeat presses hitting a server rate limit.
  <agent>     limit collection to the named agents (claude, codex, kimi, opencode)

Cache: \${HYPR_CACHE_HOME:-~/.cache/hypr}/agents/usage.json" "$@"

exec python3 "${HYPR_LIB_DIR}/system/_agent-usage.py" "$@"
