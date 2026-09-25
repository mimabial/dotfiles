#!/usr/bin/env bash
set -u

usage() { printf 'Usage: %s {list|add KIND EPOCH [LABEL]|cancel ID|restore}\n' "${0##*/}"; }
[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit; }

timer_state_dir="${XDG_STATE_HOME:-$HOME/.local/timer_state_file}/quickshell"
timer_state_file="${timer_state_dir}/timers.json"
timer_script_path="$(readlink -f "${BASH_SOURCE[0]}")"
mkdir -p "${timer_state_dir}"
[[ -s "${timer_state_file}" ]] || printf '[]\n' >"${timer_state_file}"

update_timer_state_under_lock() {
  local filter="$1" tmp="" rc=0; shift
  exec 9>"${timer_state_file}.lock"; flock 9
  tmp="$(mktemp "${timer_state_dir}/.timers.XXXXXX")" || return 1
  jq "$@" "${filter}" "${timer_state_file}" >"${tmp}" && mv "${tmp}" "${timer_state_file}" || rc=$?
  rm -f "${tmp}"; exec 9>&-; return "${rc}"
}

timer_process_is_alive() {
  [[ "$1" =~ ^[0-9]+$ && -r "/proc/$1/cmdline" ]] || return 1
  [[ "$(tr '\0' ' ' <"/proc/$1/cmdline")" == *"${timer_script_path} wait $2 "* ]]
}

start_timer_wait_process() {
  local id="$1" epoch="$2"
  nohup "${timer_script_path}" wait "${id}" "${epoch}" >/dev/null 2>&1 &
  printf 'process\t%s\n' "$!"
}

case "${1:-list}" in
  list)
    jq --argjson now "$(date +%s)" 'map(select(.epoch > $now)) | sort_by(.epoch)' "${timer_state_file}"
    ;;
  add)
    kind="${2:-}"; epoch="${3:-}"; label="${4:-}"
    [[ "${kind}" == timer || "${kind}" == alarm ]] && [[ "${epoch}" =~ ^[0-9]+$ ]] && ((epoch > $(date +%s))) || exit 2
    id="$(date +%s%N)"; IFS=$'\t' read -r backend ref < <(start_timer_wait_process "${id}" "${epoch}")
    update_timer_state_under_lock '. + [{id:$id, epoch:$epoch, kind:$kind, label:$label, backend:$backend, ref:$ref}] | sort_by(.epoch)' \
      --arg id "${id}" --argjson epoch "${epoch}" --arg kind "${kind}" --arg label "${label}" --arg backend "${backend}" --arg ref "${ref}"
    ;;
  cancel)
    id="${2:-}"; item="$(jq -c --arg id "${id}" '.[] | select(.id == $id)' "${timer_state_file}")"
    [[ -n "${item}" ]] || exit 0
    backend="$(jq -r .backend <<<"${item}")"; ref="$(jq -r .ref <<<"${item}")"
    if [[ "${backend}" == process ]] && timer_process_is_alive "${ref}" "${id}"; then kill "${ref}"; fi
    update_timer_state_under_lock 'map(select(.id != $id))' --arg id "${id}"
    ;;
  wait)
    id="${2:-}"; epoch="${3:-0}"
    while remaining=$((epoch - $(date +%s))) && ((remaining > 0)); do ((remaining > 30)) && remaining=30; sleep "${remaining}"; done
    exec "${timer_script_path}" fire "${id}"
    ;;
  fire)
    id="${2:-}"; item="$(jq -c --arg id "${id}" '.[] | select(.id == $id)' "${timer_state_file}")"
    [[ -n "${item}" ]] || exit 0
    update_timer_state_under_lock 'map(select(.id != $id))' --arg id "${id}"
    kind="$(jq -r .kind <<<"${item}")"; label="$(jq -r .label <<<"${item}")"
    [[ -n "${label}" ]] || label="$([[ "${kind}" == alarm ]] && printf 'Alarm time' || printf 'Time is up')"
    dunstify -a "Alarm" -u critical -t 0 -h "string:x-dunst-stack-tag:alarm-${id}" \
      "$([[ "${kind}" == alarm ]] && printf 'Alarm' || printf 'Timer finished')" "${label}" 2>/dev/null || true
    canberra-gtk-play -i alarm-clock-elapsed 2>/dev/null || pw-play /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null || true
    ;;
  restore)
    while IFS= read -r item; do
      id="$(jq -r .id <<<"${item}")"; epoch="$(jq -r .epoch <<<"${item}")"
      if ((epoch <= $(date +%s))); then "${timer_script_path}" fire "${id}"; continue; fi
      backend="$(jq -r .backend <<<"${item}")"; ref="$(jq -r .ref <<<"${item}")"
      [[ "${backend}" == process ]] && timer_process_is_alive "${ref}" "${id}" && continue
      IFS=$'\t' read -r backend ref < <(start_timer_wait_process "${id}" "${epoch}")
      update_timer_state_under_lock 'map(if .id == $id then .backend=$backend | .ref=$ref else . end)' --arg id "${id}" --arg backend "${backend}" --arg ref "${ref}"
    done < <(jq -c '.[]' "${timer_state_file}")
    ;;
  *) usage >&2; exit 2 ;;
esac
