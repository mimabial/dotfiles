#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

readonly USAGE="Usage: hyprshell system/agent-limit-alert <id> <name> <limit> <permille> <resets-at> <observed-at-ms>"
readonly ALERT_PERCENT=90
readonly OBSERVATION_MAX_AGE_MS=$((40 * 60 * 1000))
readonly OBSERVATION_MAX_LEAD_MS=$((5 * 60 * 1000))

hypr_help_guard "${USAGE}
Notify once when a fresh agent limit reaches ${ALERT_PERCENT}%, if enabled." "$@"

[[ $# -eq 6 && -n "$1" && "$4" =~ ^[0-9]+$ && "$6" =~ ^[0-9]+$ ]] || {
  printf '%s\n' "${USAGE}" >&2
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

((observed_at > 0 && now_ms - observed_at <= OBSERVATION_MAX_AGE_MS && observed_at - now_ms <= OBSERVATION_MAX_LEAD_MS)) || exit 0
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

if ((used_permille < ALERT_PERCENT * 10)); then
  [[ "${previous}" == fired:* ]] && write_status "ready:${resets_at}"
  exit 0
fi
[[ "${previous}" == "fired:${resets_at}" ]] && exit 0

percent=$(((used_permille + 5) / 10))
if send_ephemeral_notif "agent-limit-${key%% *}" -a "AI agents" -i applications-development \
  "Agent usage reached ${ALERT_PERCENT}%" "${agent_name}: ${percent}% of ${limit_label}"; then
  write_status "fired:${resets_at}"
fi
