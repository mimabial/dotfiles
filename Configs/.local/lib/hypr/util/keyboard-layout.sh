#!/usr/bin/env bash

source "${HOME}/.local/lib/hypr/runtime/init.bash"
set -euo pipefail
hypr_runtime_require state

hypr_help_guard "Usage: hyprshell util/keyboard-layout [OPTION]

Without options, prints the active layout and managed keyboard settings as JSON.

Options:
  --available                 list installed XKB layouts, variants, and options
  --use INDEX                 switch physical keyboards to layout INDEX
  --add LAYOUT [VARIANT]      add and activate an XKB layout/variant
  --remove INDEX              remove a configured layout safely
  --shortcut OPTION|none      set or disable the XKB group shortcut" "$@"

config_file=${HYPR_KEYBOARD_CONFIG_FILE:-${HYPR_CONFIG_HOME}/keyboard.lua}
config_lock_fd=""

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

hypr_option_string() {
  local payload="" value=""
  payload=$(hyprctl -j getoption "$1" 2>/dev/null) || return 1
  value=$(jq -er 'if (.str? | type) == "string" then .str elif (.string? | type) == "string" then .string else empty end' <<<"${payload}") || return 1
  case "${value}" in
    '[EMPTY]' | '[[EMPTY]]') printf '' ;;
    *) printf '%s\n' "${value}" ;;
  esac
}

current_payload() {
  local layouts="" variants="" options=""
  layouts=$(hypr_option_string input:kb_layout) || die 'The active keyboard layouts could not be read.'
  variants=$(hypr_option_string input:kb_variant 2>/dev/null || true)
  options=$(hypr_option_string input:kb_options 2>/dev/null || true)
  [[ -n "${layouts}" ]] || die 'Hyprland did not report a keyboard layout.'

  jq -cn --arg layouts "${layouts}" --arg variants "${variants}" --arg options "${options}" '
    ($layouts | split(",")) as $layoutList
    | ($variants | split(",")) as $variantList
    | ($options | split(",") | map(select(length > 0))) as $optionList
    | {
        layouts: [$layoutList | to_entries[] | {layout: .value, variant: ($variantList[.key] // "")}],
        switchOption: ([$optionList[] | select(startswith("grp:"))][-1] // ""),
        nonGroupOptions: [$optionList[] | select(startswith("grp:") | not)]
      }
  '
}

validate_shape() {
  jq -e '
    (.layouts | type == "array" and length > 0)
    and all(.layouts[];
      (.layout | type == "string" and test("^[A-Za-z0-9_+-]+$"))
      and (.variant | type == "string" and test("^[A-Za-z0-9_+-]*$")))
    and ([.layouts[] | [.layout, .variant]] | unique | length) == (.layouts | length)
    and (.switchOption | type == "string" and test("^(|grp:[A-Za-z0-9_+-]+)$"))
    and (.nonGroupOptions | type == "array")
    and all(.nonGroupOptions[];
      type == "string" and test("^[A-Za-z0-9_:+-]+$") and (startswith("grp:") | not))
  ' >/dev/null 2>&1 <<<"$1"
}

layout_csv() { jq -r '[.layouts[].layout] | join(",")' <<<"$1"; }
variant_csv() { jq -r '[.layouts[].variant] | join(",")' <<<"$1"; }
options_csv() { jq -r '[.nonGroupOptions[], .switchOption] | map(select(length > 0)) | join(",")' <<<"$1"; }

compile_layout() {
  xkbcli compile-keymap \
    --layout "$(layout_csv "$1")" \
    --variant "$(variant_csv "$1")" \
    --options "$(options_csv "$1")" >/dev/null 2>&1
}

is_latin() {
  local layout="$1" variant="${2:-}" letters=""
  local -a command=(xkbcli compile-keymap --layout "${layout}")
  [[ -z "${variant}" ]] || command+=(--variant "${variant}")
  letters=$("${command[@]}" 2>/dev/null \
    | sed -nE 's/.*\{[[:space:]]*\[[[:space:]]*([a-z])[[:space:]]*,.*/\1/p' \
    | sort -u | tr -d '\n')
  [[ ${#letters} -eq 26 ]]
}

validate_candidate() {
  local payload="$1" catalog="" option="" shortcut="" first_layout="" first_variant=""
  validate_shape "${payload}" || die 'Invalid keyboard-layout state; nothing was changed.'
  shortcut=$(jq -r '.switchOption' <<<"${payload}")
  if [[ -n "${shortcut}" ]] \
    && { [[ "${shortcut}" =~ _switch(_|$) ]] \
      || [[ "${shortcut}" != grp:toggle && ! "${shortcut}" =~ _toggle(_|$) && ! "${shortcut}" =~ _select$ ]]; }; then
    die 'Choose a supported XKB layout-switching shortcut; nothing was changed.'
  fi

  catalog=$(xkbcli list --load-exotic 2>/dev/null) \
    || die 'The installed XKB catalog could not be read; nothing was changed.'
  while IFS= read -r option; do
    [[ -z "${option}" ]] && continue
    grep -Fqx "  - name: '${option}'" <<<"${catalog}" \
      || die "XKB does not provide option '${option}'; nothing was changed."
  done < <(jq -r '.nonGroupOptions[], .switchOption' <<<"${payload}")
  compile_layout "${payload}" || die 'XKB rejected that layout, variant, or shortcut; nothing was changed.'

  first_layout=$(jq -r '.layouts[0].layout' <<<"${payload}")
  first_variant=$(jq -r '.layouts[0].variant' <<<"${payload}")
  is_latin "${first_layout}" "${first_variant}" \
    || die 'Keep a Latin layout first so letter keybindings remain usable.'
}

keyboard_field() {
  local field="$1"
  hyprctl devices -j 2>/dev/null | jq -r --arg field "${field}" '
    (.keyboards | map(select(.main == true))[0] // .[0] // {})[$field] // empty
  '
}

active_index() {
  local index=""
  index=$(keyboard_field active_layout_index 2>/dev/null || true)
  [[ "${index}" =~ ^[0-9]+$ ]] && printf '%s\n' "${index}" || printf '0\n'
}

status_json() {
  local payload="${1:-}" index="" count="" keymap="" code="" layouts="" tooltip=""
  [[ -n "${payload}" ]] || payload=$(current_payload)
  index=$(active_index)
  count=$(jq '.layouts | length' <<<"${payload}")
  (( index < count )) || index=0
  keymap=$(keyboard_field active_keymap 2>/dev/null || true)
  code=$(jq -r --argjson index "${index}" '.layouts[$index].layout // ""' <<<"${payload}")
  layouts=$(layout_csv "${payload}")
  tooltip=${keymap:-Unknown layout}
  [[ -z "${layouts}" ]] || tooltip+=$'\n'"${layouts}"

  jq -c \
    --arg text "${code}" \
    --arg alt "${keymap}" \
    --arg layouts "${layouts}" \
    --arg variants "$(variant_csv "${payload}")" \
    --arg options "$(options_csv "${payload}")" \
    --arg tooltip "${tooltip}" \
    --argjson activeIndex "${index}" '
      . + {
        text: $text,
        alt: $alt,
        configured: .layouts,
        layouts: $layouts,
        variants: $variants,
        options: $options,
        tooltip: $tooltip,
        activeIndex: $activeIndex
      }
    ' <<<"${payload}"
}

typed_keyboard_names() {
  hyprctl devices -j 2>/dev/null | jq -r '
    .keyboards[]?.name
    | select(test("^(power-button(-[0-9]+)?|video-bus(-[0-9]+)?|sleep-button|lid-switch|.*system-control|.*consumer-control|asus-wmi-hotkeys|hl-virtual-keyboard)") | not)
  '
}

all_keyboard_names() {
  hyprctl devices -j 2>/dev/null | jq -r '.keyboards[]?.name'
}

switch_named_checked() {
  local index="$1" names="$2" keyboard="" found=false
  while IFS= read -r keyboard; do
    [[ -z "${keyboard}" ]] && continue
    found=true
    hyprctl switchxkblayout "${keyboard}" "${index}" >/dev/null 2>&1 || return 1
  done <<<"${names}"
  [[ "${found}" == true ]]
}

switch_typed_checked() { switch_named_checked "$1" "$(typed_keyboard_names)"; }
switch_all_checked() { switch_named_checked "$1" "$(all_keyboard_names)"; }
switch_typed() { switch_typed_checked "$1" || true; }

render_config() {
  local payload="$1" target="$2"
  {
    printf '%s\n' '-- Generated by the Quickshell language module.'
    printf '%s\n' '-- Use the bar popup or hyprshell util/keyboard-layout to edit it.'
    printf '%s\n' 'hl.config({' '    input = {'
    printf '        kb_layout = %s,\n' "$(hypr_lua_quote "$(layout_csv "${payload}")")"
    printf '        kb_variant = %s,\n' "$(hypr_lua_quote "$(variant_csv "${payload}")")"
    printf '        kb_options = %s,\n' "$(hypr_lua_quote "$(options_csv "${payload}")")"
    printf '%s\n' '    },' '})'
  } >"${target}"
  chmod 0644 "${target}"
}

disable_autoreload_value() {
  hyprctl -j getoption misc:disable_autoreload 2>/dev/null \
    | jq -er '.bool | if . then "true" else "false" end'
}

set_disable_autoreload() {
  hypr_lua_apply "hl.config({ misc = { disable_autoreload = $1 } })" >/dev/null 2>&1
}

apply_live_config() {
  local payload="$1" layouts="" variants="" options=""
  layouts=$(hypr_lua_quote "$(layout_csv "${payload}")")
  variants=$(hypr_lua_quote "$(variant_csv "${payload}")")
  options=$(hypr_lua_quote "$(options_csv "${payload}")")
  hypr_lua_apply "hl.config({ input = { kb_layout = ${layouts}, kb_variant = ${variants}, kb_options = ${options} } })" >/dev/null 2>&1
}

live_matches() {
  [[ "$(hypr_option_string input:kb_layout)" == "$(layout_csv "$1")" ]] \
    && [[ "$(hypr_option_string input:kb_variant)" == "$(variant_csv "$1")" ]] \
    && [[ "$(hypr_option_string input:kb_options)" == "$(options_csv "$1")" ]]
}

restore_config() {
  local backup="$1" had_config="$2"
  if [[ "${had_config}" == true ]]; then
    cp -p -- "${backup}" "${config_file}"
  else
    rm -f -- "${config_file}"
  fi
}

commit_candidate() {
  local payload="$1" requested_index="${2:-0}" pre_apply_index="${3:-}" rollback_index="${4:-0}"
  local config_dir="" temp_config="" old_config="" old_payload="" had_config=false
  local reload_was_disabled="" reload_guarded=false

  validate_candidate "${payload}"
  config_dir=$(dirname -- "${config_file}")
  mkdir -p -- "${config_dir}"
  temp_config=$(mktemp --tmpdir="${config_dir}" .keyboard.lua.XXXXXX)
  old_config=$(mktemp --tmpdir="${config_dir}" .keyboard-old.lua.XXXXXX)
  render_config "${payload}" "${temp_config}"

  if [[ -f "${config_file}" ]] && cmp -s -- "${temp_config}" "${config_file}"; then
    rm -f -- "${temp_config}" "${old_config}"
    status_json "${payload}"
    return 0
  fi

  old_payload=$(current_payload)
  if [[ -f "${config_file}" ]]; then
    cp -p -- "${config_file}" "${old_config}"
    had_config=true
  fi

  restore_reload_guard() {
    if [[ "${reload_guarded}" == true ]]; then
      set_disable_autoreload "${reload_was_disabled}" || true
      reload_guarded=false
    fi
  }
  cleanup_keyboard_config() {
    restore_reload_guard
    rm -f -- "${temp_config}" "${old_config}"
  }
  trap cleanup_keyboard_config EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  reload_was_disabled=$(disable_autoreload_value) \
    || die 'Hyprland autoreload state could not be read; nothing was changed.'
  set_disable_autoreload true \
    || die 'Hyprland autoreload could not be paused safely; nothing was changed.'
  reload_guarded=true

  if [[ -n "${pre_apply_index}" ]] && ! switch_all_checked "${pre_apply_index}"; then
    die 'The keyboards could not be moved to a safe layout; nothing was changed.'
  fi

  mv -f -- "${temp_config}" "${config_file}"
  if ! apply_live_config "${payload}" || ! live_matches "${payload}"; then
    restore_config "${old_config}" "${had_config}"
    apply_live_config "${old_payload}" || true
    [[ -z "${pre_apply_index}" ]] || switch_typed "${rollback_index}"
    die 'Hyprland rejected the keyboard configuration; the previous settings were restored.'
  fi

  switch_typed "${requested_index}"
  restore_reload_guard
  trap - EXIT HUP INT TERM
  rm -f -- "${temp_config}" "${old_config}"
  status_json "${payload}"
}

acquire_config_lock() {
  state_acquire_lock "${config_file}" config_lock_fd \
    || die 'Keyboard settings are busy; try again in a moment.'
}

action=${1:-status}
case "${action}" in
  status)
    status_json
    ;;
  --available)
    xkbcli list --load-exotic
    ;;
  --use)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || die '--use needs a numeric layout index.'
    index=$2
    payload=$(current_payload)
    count=$(jq '.layouts | length' <<<"${payload}")
    (( index < count )) || die 'That keyboard layout is no longer configured.'
    switch_typed_checked "${index}" || die 'The physical keyboards could not be switched.'
    status_json "${payload}"
    ;;
  --add)
    layout=${2:-}; variant=${3:-}
    [[ "${layout}" =~ ^[A-Za-z0-9_+-]+$ && "${variant}" =~ ^[A-Za-z0-9_+-]*$ ]] \
      || die '--add needs a valid XKB layout and optional variant.'
    acquire_config_lock
    payload=$(current_payload)
    next=$(jq -c --arg layout "${layout}" --arg variant "${variant}" '
      if any(.layouts[]; .layout == $layout and .variant == $variant)
      then error("duplicate") else .layouts += [{layout: $layout, variant: $variant}] end
    ' <<<"${payload}" 2>/dev/null) || die 'That layout and variant is already configured.'
    commit_candidate "${next}" "$(jq '.layouts | length' <<<"${payload}")"
    ;;
  --remove)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || die '--remove needs a numeric layout index.'
    index=$2
    acquire_config_lock
    payload=$(current_payload)
    count=$(jq '.layouts | length' <<<"${payload}")
    (( count > 1 )) || die 'Keep at least one keyboard layout.'
    (( index < count )) || die 'That keyboard layout is no longer configured.'
    current=$(active_index)
    if (( index < current )); then requested=$((current - 1)); elif (( index == current )); then requested=${index}; else requested=$current; fi
    (( requested < count - 1 )) || requested=$((count - 2))
    (( index == 0 )) && safe_old_index=1 || safe_old_index=0
    next=$(jq -c --argjson index "${index}" '.layouts |= del(.[$index])' <<<"${payload}")
    commit_candidate "${next}" "${requested}" "${safe_old_index}" "${current}"
    ;;
  --shortcut)
    shortcut=${2:-}
    [[ "${shortcut}" == none ]] && shortcut=""
    [[ -z "${shortcut}" || "${shortcut}" =~ ^grp:[A-Za-z0-9_+-]+$ ]] \
      || die '--shortcut needs an XKB grp option or none.'
    acquire_config_lock
    payload=$(current_payload)
    next=$(jq -c --arg shortcut "${shortcut}" '.switchOption = $shortcut' <<<"${payload}")
    commit_candidate "${next}" "$(active_index)"
    ;;
  *)
    die "Unknown option: ${action}"
    ;;
esac
