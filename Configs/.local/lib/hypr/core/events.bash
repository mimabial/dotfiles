#!/usr/bin/env bash

hypr_event_socket() {
  printf '%s\n' "${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
}

hypr_layer_mapped() {
  hyprctl -j layers 2>/dev/null | jq -e --arg namespace "$1" '[.. | objects | .namespace?] | any(. == $namespace)' >/dev/null
}

hypr_wait_for() {
  local seconds="$1" event_glob="$2" events event="" status=1 listener
  exec {events}< <(exec timeout "${seconds}" nc -U "$(hypr_event_socket)")
  listener=$!
  shift 2
  until "$@" && status=0; do
    # shellcheck disable=SC2053 # event_glob is a pattern.
    while read -r -u "${events}" event && [[ "${event}" != ${event_glob} ]]; do :; done
    [[ -n "${event}" ]] || break
  done
  kill "${listener}" 2>/dev/null || true
  exec {events}<&-
  return "${status}"
}

hypr_wait_for_path() {
  local seconds="$1" path="$2" events line="" watcher
  exec {events}< <(exec timeout "${seconds}" inotifywait -m -e create -e moved_to --format %f "${path%/*}" 2>&1)
  watcher=$!
  until [[ "${line}" == "Watches established." ]]; do read -r -u "${events}" line || break; done
  until [[ -e "${path}" ]]; do read -r -u "${events}" line || break; done
  kill "${watcher}" 2>/dev/null || true
  exec {events}<&-
  [[ -e "${path}" ]]
}
