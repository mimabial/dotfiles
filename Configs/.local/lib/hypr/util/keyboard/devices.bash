keyboard_device_field() {
  local field="$1"
  hyprctl devices -j 2>/dev/null | jq -r --arg field "${field}" '
    (.keyboards | map(select(.main == true))[0] // .[0] // {})[$field] // empty
  '
}

keyboard_active_layout_index() {
  local index=""
  index=$(keyboard_device_field active_layout_index 2>/dev/null || true)
  [[ "${index}" =~ ^[0-9]+$ ]] && printf '%s\n' "${index}" || printf '0\n'
}

keyboard_typing_device_names() {
  hyprctl devices -j 2>/dev/null | jq -r '
    .keyboards[]?.name
    | select(test("^(power-button(-[0-9]+)?|video-bus(-[0-9]+)?|sleep-button|lid-switch|.*system-control|.*consumer-control|asus-wmi-hotkeys|hl-virtual-keyboard)") | not)
  '
}

keyboard_all_device_names() {
  hyprctl devices -j 2>/dev/null | jq -r '.keyboards[]?.name'
}

keyboard_switch_devices() {
  local index="$1" names="$2" keyboard="" found=false
  while IFS= read -r keyboard; do
    [[ -z "${keyboard}" ]] && continue
    found=true
    hyprctl switchxkblayout "${keyboard}" "${index}" >/dev/null 2>&1 || return 1
  done <<<"${names}"
  [[ "${found}" == true ]]
}

keyboard_switch_typing_devices() { keyboard_switch_devices "$1" "$(keyboard_typing_device_names)"; }

keyboard_switch_all_devices() { keyboard_switch_devices "$1" "$(keyboard_all_device_names)"; }

keyboard_restore_typing_devices() { keyboard_switch_typing_devices "$1" || true; }
