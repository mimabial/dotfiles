#!/usr/bin/env bash
set -u

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
state="${state_dir}/timers.json"
self="$(readlink -f "${BASH_SOURCE[0]}")"
mkdir -p "${state_dir}"
[[ -s "${state}" ]] || printf '[]\n' >"${state}"

write_state() {
  local filter="$1" tmp="" rc=0; shift
  exec 9>"${state}.lock"; flock 9
  tmp="$(mktemp "${state_dir}/.timers.XXXXXX")" || return 1
  jq "$@" "${filter}" "${state}" >"${tmp}" && mv "${tmp}" "${state}" || rc=$?
  rm -f "${tmp}"; exec 9>&-; return "${rc}"
}

process_alive() {
  [[ "$1" =~ ^[0-9]+$ && -r "/proc/$1/cmdline" ]] || return 1
  [[ "$(tr '\0' ' ' <"/proc/$1/cmdline")" == *"${self} wait $2 "* ]]
}

schedule() {
  local id="$1" epoch="$2" unit="quickshell-alarm-$1" when=""
  if command -v systemd-run >/dev/null && systemctl --user is-system-running >/dev/null 2>&1; then
    when="$(date -d "@${epoch}" '+%Y-%m-%d %H:%M:%S')"
    if systemd-run --user --quiet --collect --unit="${unit}" --on-calendar="${when}" \
      --timer-property=AccuracySec=1s --timer-property=Persistent=true "${self}" fire "${id}"; then
      printf 'systemd\t%s\n' "${unit}"; return
    fi
  fi
  nohup "${self}" wait "${id}" "${epoch}" >/dev/null 2>&1 &
  printf 'process\t%s\n' "$!"
}

case "${1:-list}" in
  list)
    jq --argjson now "$(date +%s)" 'map(select(.epoch > $now)) | sort_by(.epoch)' "${state}"
    ;;
  add)
    kind="${2:-}"; epoch="${3:-}"; label="${4:-}"
    [[ "${kind}" == timer || "${kind}" == alarm ]] && [[ "${epoch}" =~ ^[0-9]+$ ]] && ((epoch > $(date +%s))) || exit 2
    id="$(date +%s%N)"; IFS=$'\t' read -r backend ref < <(schedule "${id}" "${epoch}")
    write_state '. + [{id:$id, epoch:$epoch, kind:$kind, label:$label, backend:$backend, ref:$ref}] | sort_by(.epoch)' \
      --arg id "${id}" --argjson epoch "${epoch}" --arg kind "${kind}" --arg label "${label}" --arg backend "${backend}" --arg ref "${ref}"
    ;;
  cancel)
    id="${2:-}"; item="$(jq -c --arg id "${id}" '.[] | select(.id == $id)' "${state}")"
    [[ -n "${item}" ]] || exit 0
    backend="$(jq -r .backend <<<"${item}")"; ref="$(jq -r .ref <<<"${item}")"
    if [[ "${backend}" == systemd && "${ref}" =~ ^quickshell-alarm-[0-9]+$ ]]; then
      systemctl --user stop "${ref}.timer" "${ref}.service" >/dev/null 2>&1 || true
    elif [[ "${backend}" == process ]] && process_alive "${ref}" "${id}"; then kill "${ref}"; fi
    write_state 'map(select(.id != $id))' --arg id "${id}"
    ;;
  wait)
    id="${2:-}"; epoch="${3:-0}"
    while remaining=$((epoch - $(date +%s))) && ((remaining > 0)); do ((remaining > 30)) && remaining=30; sleep "${remaining}"; done
    exec "${self}" fire "${id}"
    ;;
  fire)
    id="${2:-}"; item="$(jq -c --arg id "${id}" '.[] | select(.id == $id)' "${state}")"
    [[ -n "${item}" ]] || exit 0
    write_state 'map(select(.id != $id))' --arg id "${id}"
    kind="$(jq -r .kind <<<"${item}")"; label="$(jq -r .label <<<"${item}")"
    [[ -n "${label}" ]] || label="$([[ "${kind}" == alarm ]] && printf 'Alarm time' || printf 'Time is up')"
    dunstify -a "Alarm" -u critical -t 0 -h "string:x-dunst-stack-tag:alarm-${id}" \
      "$([[ "${kind}" == alarm ]] && printf 'Alarm' || printf 'Timer finished')" "${label}" 2>/dev/null || true
    canberra-gtk-play -i alarm-clock-elapsed 2>/dev/null || pw-play /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null || true
    ;;
  restore)
    while IFS= read -r item; do
      id="$(jq -r .id <<<"${item}")"; epoch="$(jq -r .epoch <<<"${item}")"
      if ((epoch <= $(date +%s))); then "${self}" fire "${id}"; continue; fi
      backend="$(jq -r .backend <<<"${item}")"; ref="$(jq -r .ref <<<"${item}")"
      { [[ "${backend}" == systemd ]] && systemctl --user is-active --quiet "${ref}.timer"; } || \
        { [[ "${backend}" == process ]] && process_alive "${ref}" "${id}"; } && continue
      IFS=$'\t' read -r backend ref < <(schedule "${id}" "${epoch}")
      write_state 'map(if .id == $id then .backend=$backend | .ref=$ref else . end)' --arg id "${id}" --arg backend "${backend}" --arg ref "${ref}"
    done < <(jq -c '.[]' "${state}")
    ;;
  *) printf 'Usage: %s {list|add KIND EPOCH [LABEL]|cancel ID|restore}\n' "${0##*/}" >&2; exit 2 ;;
esac
