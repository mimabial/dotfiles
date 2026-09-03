#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/agent-recommendation <id> <name> [usage-summary]
Record the current AI-agent recommendation and notify only when it changes." "$@"

[[ $# -ge 2 && $# -le 3 ]] || {
  printf 'Usage: hyprshell system/agent-recommendation <id> <name> [usage-summary]\n' >&2
  exit 2
}

readonly agent_id="$1"
readonly agent_name="$2"
readonly usage_summary="${3:-}"
readonly state_dir="${HYPR_STATE_HOME}/agents"
readonly state_file="${state_dir}/recommendation"

mkdir -p "${state_dir}"
exec {lock_fd}>"${state_file}.lock"
flock "${lock_fd}"

previous=""
[[ -r "${state_file}" ]] && read -r previous <"${state_file}" || true
[[ "${previous}" == "${agent_id}" ]] && exit 0

tmp="$(mktemp "${state_file}.XXXXXX")"
trap 'rm -f "${tmp}"' EXIT
printf '%s\n' "${agent_id}" >"${tmp}"
mv -f "${tmp}" "${state_file}"
trap - EXIT
flock -u "${lock_fd}"

[[ -n "${previous}" ]] || exit 0
body="Use ${agent_name}"
[[ -n "${usage_summary}" ]] && body+=$'\n'"${usage_summary}"
send_ephemeral_notif "agent-recommendation" -a "AI agents" -i applications-development \
  "Agent recommendation changed" "${body}" || true
