source "${BASH_SOURCE[0]%/*}/state.bash"
source "${BASH_SOURCE[0]%/*}/controller.bash"
if ! declare -F notify_send_safe >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/../../core/notify.bash"
fi

idle_toggle_setting() {
  local -n setting_ref="$1"
  local transition=enabled value=1
  if "${setting_ref[enabled_fn]}"; then transition=disabled; value=0; fi
  "${setting_ref[setter_fn]}" "${value}"
  local -a notification=(-t "${NOTIFY_MS}" -i "${setting_ref[${transition}_icon]}" "${setting_ref[${transition}_summary]}")
  [[ -z "${setting_ref[${transition}_body]:-}" ]] || notification+=("${setting_ref[${transition}_body]}")
  if command -v dunstify >/dev/null 2>&1; then dunstify "${notification[@]}"; fi
  idle_ensure_manager_running
  idle_notify_manager
}
