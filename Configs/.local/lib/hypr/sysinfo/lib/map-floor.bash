#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# map_floor MAPPING NUM: from a high->low ordered "key:value, key:value, ..."
# list, print the value of the first pair whose key is below NUM. A trailing
# bare token (no ':') is the default; with none, no match prints a single space.
# Shared by sysinfo/cpuinfo.sh and sysinfo/gpuinfo.render.bash.
map_floor() {
  local mapping="$1"
  local input="$2"
  local def_val=""
  local pair=""
  local key=""
  local value=""
  local num="${input%%.*}"
  local -a pairs=()

  IFS=', ' read -r -a pairs <<<"${mapping}"
  if [[ ${pairs[-1]} != *":"* ]]; then
    def_val="${pairs[-1]}"
    unset 'pairs[${#pairs[@]}-1]'
  fi

  for pair in "${pairs[@]}"; do
    IFS=':' read -r key value <<<"${pair}"
    # Bash integer compare avoids spawning awk on this hot path.
    if [[ "$num" =~ ^-?[0-9]+$ && "$key" =~ ^-?[0-9]+$ ]]; then
      (( num > key )) && printf '%s\n' "${value}" && return
    elif [[ -n "$num" && -n "$key" && "$num" > "$key" ]]; then
      printf '%s\n' "${value}" && return
    fi
  done

  [[ -n "${def_val}" ]] && printf '%s\n' "${def_val}" || printf ' \n'
}
