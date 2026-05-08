#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

hypr_stateful_choice_resolve_path() {
  local name="$1"
  local extension="$2"
  local user_dir="$3"
  local shared_dir="$4"
  local candidate=""

  name="${name%.${extension}}"
  if [[ "${name}" == */* ]] && [[ -f "${name}" ]]; then
    printf '%s\n' "${name}"
    return 0
  fi

  for candidate in \
    "${user_dir}/${name}.${extension}" \
    "${shared_dir}/${name}.${extension}"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

hypr_stateful_choice_list_names() {
  local extension="$1"
  local user_dir="$2"
  local shared_dir="$3"
  shift 3
  local dir=""
  local path=""
  local name=""
  local skip_name=""
  local -A seen=()
  local -A skip=()

  for skip_name in "$@"; do
    skip["${skip_name}"]=1
  done

  for dir in "${user_dir}" "${shared_dir}"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r -d '' path; do
      name="$(basename "${path}" ".${extension}")"
      [[ -n "${skip[${name}]:-}" || -n "${seen[${name}]:-}" ]] && continue
      seen["${name}"]=1
      printf '%s\n' "${name}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name "*.${extension}" -print0 | sort -z)
  done
}

hypr_stateful_choice_select() {
  local title="$1"
  local prompt="$2"
  local icon="$3"
  local scale="$4"
  local font="$5"
  local current="$6"
  local items="$7"
  local -n selected_ref="$8"
  local -a rofi_args=()

  rofi_build_standard_menu_args rofi_args "${title}" "${prompt}" "${icon}" "${scale}" "${font}"
  [[ -n "${current}" ]] && rofi_args+=(-select "${current}")
  selected_ref="$(printf '%s\n' "${items}" | sed '/^$/d' | rofi "${rofi_args[@]}")"
}

hypr_stateful_choice_apply() {
  local state_key="$1"
  local value="$2"
  local notify_tag="$3"
  local notify_title="$4"
  local update_fn="$5"

  state_set "${state_key}" "${value}" "staterc"
  "${update_fn}" "${value}"
  send_ephemeral_notif "${notify_tag}" -t 2000 -i "preferences-desktop-display" "${notify_title}" "${value}"
}
