# Keep the last state only for optional Mullvad auto-reconnect. Mullvad owns its
# notifications; custom action notifications belong to NetworkManager.
vpn_record_status_and_reconnect() {
  local -n recorded_status_ref="$1" reconnect_options_ref="$2"
  local runtime_dir="${HYPR_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/${UID}}/hypr}" state_file="" previous_state=""
  local connection="${recorded_status_ref[connection]}"

  [[ -d "${runtime_dir}" ]] || mkdir -p "${runtime_dir}" 2>/dev/null || return 0
  [[ -w "${runtime_dir}" ]] || return 0
  state_file="${runtime_dir}/quickshell-vpn-last"

  [[ -f "${state_file}" ]] && previous_state="$(<"${state_file}")"
  [[ "${previous_state}" == "${connection}" ]] || printf '%s\n' "${connection}" >"${state_file}" || true
  case "${previous_state}:${connection}" in
    connected:disconnected | connected:error | connected:none)
      if [[ "${reconnect_options_ref[auto_reconnect]}" == true ]] && command -v mullvad >/dev/null 2>&1; then
        mullvad connect >/dev/null 2>&1 || true
      fi
      ;;
  esac
}
