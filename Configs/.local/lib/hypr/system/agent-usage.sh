#!/usr/bin/env bash
# Emit one display-ready JSON usage record per AI coding subscription, as a
# JSON array. Mirrors omarchy-agent-usage-update's contract: each collector
# prints one record, adding an agent is adding a collector.
#
# Collecting is slow (it scans the agents' local state), so producer and
# display are split the way omarchy splits them: --write refreshes a cache
# file and the bar watches that file, rather than blocking on a scan.
#
# Collectors are looked up on PATH first, then in ~/omarchy/ if that reference
# checkout is present. Emits [] when none are installed, so callers can treat
# "no agents" and "no collectors" the same way.
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/agent-usage [--write] [agent...]
  (no args)   print a JSON array of records for every agent that reports usage
  --write     refresh the cache the bar reads instead of printing
  <agent>     limit collection to the named agents (claude, codex, fireworks)

Cache: \${HYPR_CACHE_HOME:-~/.cache/hypr}/agents/usage.json" "$@"

readonly AGENTS=(claude codex fireworks)
readonly FALLBACK_DIR="${HOME}/omarchy/bin"
readonly CACHE_DIR="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/agents"
readonly CACHE_FILE="${CACHE_DIR}/usage.json"

collector_for() {
  local name="omarchy-agent-usage-$1"
  if command -v "${name}" >/dev/null 2>&1; then
    command -v "${name}"
  elif [[ -x "${FALLBACK_DIR}/${name}" ]]; then
    printf '%s\n' "${FALLBACK_DIR}/${name}"
  fi
}

write=0
wanted=()
for arg in "$@"; do
  case "${arg}" in
    --write) write=1 ;;
    *) wanted+=("${arg}") ;;
  esac
done
[[ ${#wanted[@]} -eq 0 ]] && wanted=("${AGENTS[@]}")

records=()
for agent in "${wanted[@]}"; do
  collector="$(collector_for "${agent}")"
  [[ -n "${collector}" ]] || continue
  record="$("${collector}" 2>/dev/null || true)"
  # A collector with nothing to report exits quietly rather than emitting a stub.
  [[ -n "${record}" ]] && jq -e . >/dev/null 2>&1 <<<"${record}" && records+=("${record}")
done

if [[ ${#records[@]} -eq 0 ]]; then
  payload='[]'
else
  payload="$(printf '%s\n' "${records[@]}" | jq -s -c .)"
fi

if ((write)); then
  mkdir -p "${CACHE_DIR}"
  tmp="$(mktemp "${CACHE_FILE}.XXXXXX")"
  trap 'rm -f "${tmp}"' EXIT
  printf '%s\n' "${payload}" >"${tmp}"
  mv -f "${tmp}" "${CACHE_FILE}"          # atomic, so the watcher never sees a partial file
  trap - EXIT
  print_log -sec "agent-usage" -stat "cached" "$(jq -r 'length' <<<"${payload}") record(s)"
else
  printf '%s\n' "${payload}"
fi
