#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/agent-usage [--write] [--force] [agent...]
  (no args)   print a JSON array of records for every agent that reports usage
  --write     refresh the cache the bar reads instead of printing
  --force     rescan local usage now, for a person who asked rather than for a
              periodic refresh. The limits probe keeps its own short window,
              which is what stops repeat presses hitting a server rate limit.
  <agent>     limit collection to the named agents (claude, codex)

Cache: \${HYPR_CACHE_HOME:-~/.cache/hypr}/agents/usage.json" "$@"

readonly AGENTS=(claude codex)
readonly COLLECTOR_DIR="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system"
readonly CACHE_DIR="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/agents"
readonly CACHE_FILE="${CACHE_DIR}/usage.json"

collector_for() {
  local collector="${COLLECTOR_DIR}/agent-usage-$1.py"
  [[ -x "${collector}" ]] && printf '%s\n' "${collector}"
}

write=0
force=0
wanted=()
for arg in "$@"; do
  case "${arg}" in
    --write) write=1 ;;
    --force) force=1 ;;
    -*) printf '%s: unknown option: %s\n' "${0##*/}" "${arg}" >&2; exit 2 ;;
    *) wanted+=("${arg}") ;;
  esac
done
[[ ${#wanted[@]} -eq 0 ]] && wanted=("${AGENTS[@]}")

scratch="$(mktemp -d "${TMPDIR:-/tmp}/agent-usage.XXXXXX")"
cleanup_paths=("${scratch}")
trap 'rm -rf "${cleanup_paths[@]}"' EXIT

# Collectors are independent and network-bound, so run them concurrently.
collector_args=()
((force)) && collector_args+=(--force)

pids=()
slots=()
for agent in "${wanted[@]}"; do
  collector="$(collector_for "${agent}")"
  [[ -n "${collector}" ]] || continue
  slots+=("${scratch}/${#pids[@]}")
  "${collector}" "${collector_args[@]}" >"${slots[-1]}" 2>/dev/null &
  pids+=("$!")
done

records=()
for index in "${!pids[@]}"; do
  wait "${pids[index]}" 2>/dev/null || true
  record="$(<"${slots[index]}")"
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
  cleanup_paths+=("${tmp}")
  printf '%s\n' "${payload}" >"${tmp}"
  mv -f "${tmp}" "${CACHE_FILE}"
  print_log -sec "agent-usage" -stat "cached" "${#records[@]} record(s)"
else
  printf '%s\n' "${payload}"
fi
