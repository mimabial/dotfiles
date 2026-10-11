TODO_CARRY_STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/task-carries.json"

todoman_available() {
  command -v todo >/dev/null 2>&1
}

exit_with_todo_error() {
  jq -n --arg error "$1" '{todos: [], error: $error}'
  exit 1
}

emit_todos() {
  local include_completed=$1
  local -a args=(--porcelain list)
  local carry_mode=advance
  if [[ "${include_completed}" -eq 1 ]]; then
    args+=(--status ANY)
    carry_mode=read
  fi
  mkdir -p "${TODO_CARRY_STATE_FILE%/*}"
  (
    flock -x 9
    python3 "${calendar_library}/todo_carry.py" \
      "${XDG_CACHE_HOME:-$HOME/.cache}/todoman/cache.sqlite3" "${TODO_CARRY_STATE_FILE}" "${carry_mode}" \
      < <(todo "${args[@]}" 2>/dev/null)
  ) 9>"${TODO_CARRY_STATE_FILE}.lock" || printf '{"todos":[]}\n'
}

resolve_todo_file_by_id() {
  python3 "${calendar_library}/resolve_todo_file.py" "$1" 2>/dev/null
}

delete_todo() {
  todo delete --yes "$1" >/dev/null 2>&1
}

complete_todo() {
  todo "done" "$1" >/dev/null 2>&1
}

reopen_todo() {
  local file tmp
  file="$(resolve_todo_file_by_id "$1")" || return 1
  [[ -n "${file}" ]] || return 1
  tmp="$(mktemp)" || return 1
  awk '
    { sub(/\r$/, "") }
    /^COMPLETED[;:]/ { next }
    /^PERCENT-COMPLETE[;:]/ { next }
    /^STATUS[;:]/ { print "STATUS:NEEDS-ACTION"; next }
    { print }
  ' "${file}" >"${tmp}" || { rm -f "${tmp}"; return 1; }
  mv -- "${tmp}" "${file}" || { rm -f "${tmp}"; return 1; }
}

edit_todo() {
  local id=$1 new_title=$2 new_priority=$3 file
  file="$(resolve_todo_file_by_id "${id}")" || return 1
  python3 "${calendar_library}/edit_todo_file.py" "${file}" "${new_title}" "${new_priority}"
}

add_todo() {
  local new_title=$1 list=$2 due_day=$3 due_at=$4 new_priority=$5 tag
  shift 5
  local -a command=(new)
  [[ -z "${list}" ]] || command+=(--list "${list}")
  [[ -z "${due_day}" ]] || command+=(--due "${due_day}${due_at:+ ${due_at}}")
  [[ -z "${new_priority}" ]] || command+=(--priority "${new_priority}")
  for tag; do
    command+=(-c "${tag}")
  done
  todo "${command[@]}" "${new_title}" >/dev/null 2>&1
}
