#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/agent-limit-alert <id> <name> <limit> <permille> <resets-at> <observed-at-ms>
Notify once when a fresh agent limit reaches 90%, if enabled." "$@"

[[ $# -eq 6 && -n "$1" && "$4" =~ ^[0-9]+$ && "$6" =~ ^[0-9]+$ ]] || {
  printf 'Usage: hyprshell system/agent-limit-alert <id> <name> <limit> <permille> <resets-at> <observed-at-ms>\n' >&2
  exit 2
}

readonly agent_id="$1"
readonly agent_name="$2"
readonly limit_label="$3"
readonly used_permille="$4"
readonly resets_at="$5"
readonly observed_at="$6"
now_ms="$(date +%s%3N)"
readonly now_ms

((observed_at > 0 && now_ms - observed_at <= 2400000 && observed_at - now_ms <= 300000)) || exit 0
jq -e '.notifyLimit == true' "${XDG_CONFIG_HOME}/quickshell/agents.json" >/dev/null 2>&1 || exit 0

readonly state_dir="${HYPR_STATE_HOME}/agents"
key="$(printf '%s\0' "${agent_id}" "${limit_label}" | sha256sum)"
readonly state_file="${state_dir}/limit-${key%% *}"
mkdir -p "${state_dir}"
exec {lock_fd}>"${state_file}.lock"
flock "${lock_fd}"

previous=""
[[ -r "${state_file}" ]] && read -r previous <"${state_file}" || true

write_status() {
  local tmp
  tmp="$(mktemp "${state_file}.XXXXXX")"
  printf '%s\n' "$1" >"${tmp}"
  mv -f "${tmp}" "${state_file}"
}

if ((used_permille < 900)); then
  [[ "${previous}" == fired:* ]] && write_status "ready:${resets_at}"
  exit 0
fi
[[ "${previous}" == "fired:${resets_at}" ]] && exit 0

percent=$(((used_permille + 5) / 10))
if send_ephemeral_notif "agent-limit-${key%% *}" -a "AI agents" -i applications-development \
  "Agent usage reached 90%" "${agent_name}: ${percent}% of ${limit_label}"; then
  write_status "fired:${resets_at}"
fi
