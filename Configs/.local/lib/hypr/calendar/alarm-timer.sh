#!/usr/bin/env bash
set -u

usage() { printf 'Usage: %s {list|add KIND EPOCH [LABEL]|cancel ID|restore}\n\nList, add, cancel and restore the alarms and timers behind the calendar popup.\n' "${0##*/}"; }
[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit; }
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/notify.bash"

timer_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
timer_state_file="${timer_state_dir}/timers.json"
timer_script_path="$(readlink -f "${BASH_SOURCE[0]}")"
exec_at="${timer_script_path%/*}/lib/exec_at.py"
[[ -d "${timer_state_dir}" ]] || mkdir -p "${timer_state_dir}"
[[ -s "${timer_state_file}" ]] || printf '[]\n' >"${timer_state_file}"

update_timer_state_under_lock() {
  local filter="$1" tmp="" rc=0; shift
  exec 9>"${timer_state_file}.lock"; flock 9
  tmp="$(mktemp "${timer_state_dir}/.timers.XXXXXX")" || return 1
  jq "$@" "${filter}" "${timer_state_file}" >"${tmp}" && mv "${tmp}" "${timer_state_file}" || rc=$?
  rm -f "${tmp}"; exec 9>&-; return "${rc}"
}

timer_process_is_alive() {
  local pid="$1" id="$2" joined=""
  local -a cmdline=()

  [[ "${pid}" =~ ^[0-9]+$ && -r "/proc/${pid}/cmdline" ]] || return 1
  mapfile -d '' cmdline <"/proc/${pid}/cmdline"
  printf -v joined '%s ' "${cmdline[@]}"
  [[ "${joined}" == *"${timer_script_path} fire ${id} "* ]]
}

start_timer_wait_process() {
  local id="$1" epoch="$2"
  nohup python3 "${exec_at}" "${epoch}" "${timer_script_path}" fire "${id}" >/dev/null 2>&1 &
  printf '%s\n' "$!"
}

case "${1:-list}" in
  list)
    jq --argjson now "${EPOCHSECONDS}" 'map(select(.epoch > $now)) | sort_by(.epoch)' "${timer_state_file}"
    ;;
  add)
    kind="${2:-}"; epoch="${3:-}"; label="${4:-}"
    [[ "${kind}" == timer || "${kind}" == alarm ]] && [[ "${epoch}" =~ ^[0-9]+$ ]] && ((epoch > EPOCHSECONDS)) || exit 2
    id="${EPOCHREALTIME/./}000"; pid="$(start_timer_wait_process "${id}" "${epoch}")"
    update_timer_state_under_lock '. + [{id:$id, epoch:$epoch, kind:$kind, label:$label, pid:$pid}] | sort_by(.epoch)' \
      --arg id "${id}" --argjson epoch "${epoch}" --arg kind "${kind}" --arg label "${label}" --arg pid "${pid}"
    ;;
  cancel)
    id="${2:-}"; item="$(jq -c --arg id "${id}" '.[] | select(.id == $id)' "${timer_state_file}")"
    [[ -n "${item}" ]] || exit 0
    pid="$(jq -r .pid <<<"${item}")"
    if timer_process_is_alive "${pid}" "${id}"; then kill "${pid}"; fi
    update_timer_state_under_lock 'map(select(.id != $id))' --arg id "${id}"
    ;;
  fire)
    id="${2:-}"; item="$(jq -c --arg id "${id}" '.[] | select(.id == $id)' "${timer_state_file}")"
    [[ -n "${item}" ]] || exit 0
    update_timer_state_under_lock 'map(select(.id != $id))' --arg id "${id}"
    kind="$(jq -r .kind <<<"${item}")"; label="$(jq -r .label <<<"${item}")"
    [[ -n "${label}" ]] || label="$([[ "${kind}" == alarm ]] && printf 'Alarm time' || printf 'Time is up')"
    dunstify -a "Alarm" -u critical -t "${NOTIFY_STICKY_MS}" -h "string:x-dunst-stack-tag:alarm-${id}" \
      "$([[ "${kind}" == alarm ]] && printf 'Alarm' || printf 'Timer finished')" "${label}" 2>/dev/null || true
    canberra-gtk-play -i alarm-clock-elapsed 2>/dev/null || pw-play /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null || true
    ;;
  restore)
    while IFS=$'\t' read -r id epoch pid; do
      if ((epoch <= EPOCHSECONDS)); then "${timer_script_path}" fire "${id}"; continue; fi
      timer_process_is_alive "${pid}" "${id}" && continue
      pid="$(start_timer_wait_process "${id}" "${epoch}")"
      update_timer_state_under_lock 'map(if .id == $id then .pid=$pid else . end)' --arg id "${id}" --arg pid "${pid}"
    done < <(jq -r '.[] | [(.id // "null"), (.epoch // 0), (.pid // "null")] | @tsv' "${timer_state_file}")
    ;;
  *) usage >&2; exit 2 ;;
esac
