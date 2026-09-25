#!/usr/bin/env bash

# Sets cores and mem_avail_kb/mem_avail_mb for callers sizing parallel work.
# MemAvailable is absent on very old kernels, hence the MemTotal fallback.
hypr_read_host_capacity() {
  cores="$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  [[ "${cores}" =~ ^[0-9]+$ ]] || cores=1

  mem_avail_kb="$(awk '/MemAvailable/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  [[ -n "${mem_avail_kb}" ]] \
    || mem_avail_kb="$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  [[ "${mem_avail_kb}" =~ ^[0-9]+$ ]] || mem_avail_kb=0
  mem_avail_mb=$((mem_avail_kb / 1024))
}

hypr_help_guard() {
  local usage_text="${1:-}"
  shift || true

  local arg=""
  for arg in "$@"; do
    case "${arg}" in
      --) break ;;
      -h | --help)
        printf '%s\n' "${usage_text}"
        exit 0
        ;;
    esac
  done
}

hypr_init_system() {
  if [[ -n "${HYPR_INIT_SYSTEM:-}" ]]; then
    printf '%s\n' "${HYPR_INIT_SYSTEM}"
    return 0
  fi

  local detected="other"
  if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    detected="systemd"
  elif command -v sv >/dev/null 2>&1 && { [[ -d /run/runit ]] || [[ -d /etc/runit ]]; }; then
    detected="runit"
  fi

  export HYPR_INIT_SYSTEM="${detected}"
  printf '%s\n' "${detected}"
}

hypr_user_sv_dir() {
  printf '%s\n' "${HYPR_USER_SV_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sv}"
}

hypr_svc_user() {
  local action="${1:-}" name="${2:-}"
  [[ -n "${action}" && -n "${name}" ]] || return 2

  hypr_init_system >/dev/null
  case "$HYPR_INIT_SYSTEM" in
    systemd)
      local unit="${name%.service}.service"
      case "${action}" in
        start)     systemctl --user start --no-block "${unit}" >/dev/null 2>&1 ;;
        stop)      systemctl --user stop "${unit}" >/dev/null 2>&1 ;;
        restart)   systemctl --user restart "${unit}" >/dev/null 2>&1 ;;
        is-active) systemctl --user is-active --quiet "${unit}" >/dev/null 2>&1 ;;
        status)    systemctl --user status "${unit}" --no-pager ;;
        enable)    systemctl --user enable "${unit}" ;;
        disable)   systemctl --user disable "${unit}" ;;
        reset-failed) systemctl --user reset-failed "${unit}" >/dev/null 2>&1 ;;
        *) return 2 ;;
      esac
      ;;
    runit)
      command -v sv >/dev/null 2>&1 || return 1
      local svc="${name%.service}"
      local sv_dir; sv_dir="$(hypr_user_sv_dir)"
      local svc_dir="${sv_dir}/${svc}"
      case "${action}" in
        start)     SVDIR="${sv_dir}" sv up "${svc}" >/dev/null 2>&1 ;;
        stop)      SVDIR="${sv_dir}" sv down "${svc}" >/dev/null 2>&1 ;;
        restart)   SVDIR="${sv_dir}" sv restart "${svc}" >/dev/null 2>&1 ;;
        is-active) SVDIR="${sv_dir}" sv status "${svc}" 2>/dev/null | grep -q '^run:' ;;
        status)    SVDIR="${sv_dir}" sv status "${svc}" ;;
        enable)    [[ -d "${svc_dir}" ]] && rm -f -- "${svc_dir}/down" ;;
        disable)   [[ -d "${svc_dir}" ]] && : >"${svc_dir}/down" ;;
        reset-failed) return 0 ;;
        *) return 2 ;;
      esac
      ;;
    *)
      case "$action" in is-active | status | enable | disable) return 1 ;; *) return 0 ;; esac
      ;;
  esac
}

hypr_svc_user_signal() {
  local name="${1:-}" sig="${2:-}"
  [[ -n "${name}" && -n "${sig}" ]] || return 2

  hypr_init_system >/dev/null
  case "$HYPR_INIT_SYSTEM" in
    systemd)
      systemctl --user kill --signal="${sig}" "${name%.service}.service" >/dev/null 2>&1
      ;;
    runit)
      command -v sv >/dev/null 2>&1 || return 1
      local sv_cmd=""
      case "${sig#SIG}" in
        USR1) sv_cmd="1" ;;
        USR2) sv_cmd="2" ;;
        HUP)  sv_cmd="hup" ;;
        TERM) sv_cmd="term" ;;
        INT)  sv_cmd="interrupt" ;;
        KILL) sv_cmd="kill" ;;
        *) return 1 ;;
      esac
      SVDIR="$(hypr_user_sv_dir)" sv "${sv_cmd}" "${name%.service}" >/dev/null 2>&1
      ;;
    *)
      return 0
      ;;
  esac
}

hypr_lua_quote() {
  jq -Rn --arg value "${1:-}" '$value'
}

hypr_lua_dispatch() {
  local expression="${1:-}"
  [[ -n "${expression}" ]] || return 1
  hyprctl dispatch "${expression}"
}

hypr_lua_batch() {
  local expression=""
  local batch=""

  for expression in "$@"; do
    [[ -n "${expression}" ]] || continue
    batch+="${batch:+;}dispatch ${expression}"
  done

  [[ -n "${batch}" ]] || return 0
  hyprctl -q --batch "${batch}"
}

hypr_lua_apply() {
  local statement="${1:-}"
  [[ -n "${statement}" ]] || return 1
  hypr_lua_dispatch "(function() ${statement}; return hl.dsp.no_op() end)()"
}

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

hypr_user_uid() {
  printf '%s\n' "$UID"
}

hypr_user_pgrep() {
  local user_uid=""

  user_uid="$(hypr_user_uid)" || return 1
  pgrep -u "${user_uid}" "$@"
}

hypr_user_pkill() {
  local user_uid=""

  user_uid="$(hypr_user_uid)" || return 1
  pkill -u "${user_uid}" "$@"
}

# Bitwarden desktop has no lock command and locks only on a ScreenSaver D-Bus signal
# nothing here emits, so quitting it is its lock.
hypr_lock_password_managers() {
  quickshell ipc call bitwarden screenLocked </dev/null >/dev/null 2>&1 &
  hypr_user_pkill -f '^/usr/lib/electron[0-9]*/electron /usr/lib/bitwarden/app\.asar' || true
}

hypr_dbus_get() {
  local reply=""

  reply="$(dbus-send "--$1" --print-reply=literal --dest="$2" "$3" org.freedesktop.DBus.Properties.Get "string:$4" "string:$5" 2>/dev/null)" || return
  printf '%s\n' "${reply##* }"
}

hypr_dbus_set() {
  dbus-send "--$1" --print-reply=literal --reply-timeout=5000 --dest="$2" "$3" org.freedesktop.DBus.Properties.Set "string:$4" "string:$5" "variant:$6:$7" >/dev/null
}

hypr_gamemode_active() {
  local clients=""

  clients="$(hypr_dbus_get session com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount)" && ((clients > 0))
}

hypr_on_battery() {
  [[ "$(hypr_dbus_get system org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery)" == true ]]
}

hypr_power_profile() {
  hypr_dbus_get system org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile
}

hypr_set_power_profile() {
  hypr_dbus_set system org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile string "$1"
}

hypr_runtime_root_dir() {
  local user_uid=""
  local runtime_dir=""
  local fallback_dir=""

  user_uid="$(hypr_user_uid)" || return 1
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/${user_uid}}"
  if [[ -n "${runtime_dir}" ]] && { [[ -d "$runtime_dir" ]] || mkdir -p "$runtime_dir" 2>/dev/null; }; then
    printf '%s\n' "${runtime_dir}"
    return 0
  fi

  fallback_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/runtime"
  [[ -d "$fallback_dir" ]] || mkdir -p "$fallback_dir" || return 1
  printf '%s\n' "${fallback_dir}"
}

hypr_runtime_subdir() {
  local subdir="${1:-}"
  local runtime_root=""
  local target_dir=""

  runtime_root="$(hypr_runtime_root_dir)" || return 1
  if [[ -z "${subdir}" ]]; then
    printf '%s\n' "${runtime_root}"
    return 0
  fi

  target_dir="${runtime_root}/${subdir#/}"
  mkdir -p "${target_dir}" || return 1
  printf '%s\n' "${target_dir}"
}

hypr_core_file() {
  local rel_path="$1"
  local config_home="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local data_home="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}"
  local shared_file="${data_home}/${rel_path}"
  local user_file="${config_home}/${rel_path}"

  if [[ -f "${shared_file}" ]]; then
    printf '%s\n' "${shared_file}"
  elif [[ -f "${user_file}" ]]; then
    printf '%s\n' "${user_file}"
  else
    printf '%s\n' "${shared_file}"
  fi
}

hypr_variables_file() {
  hypr_core_file "variables.meta"
}

# Output order is the layer precedence (first wins) and is relied on
# positionally by theme_desktop_resolve_base_values (desktop.sync.bash):
# userfonts.lua, themes/theme.meta, variables.meta. Change both together.
hypr_config_layer_files() {
  local config_home="${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
  local data_home="${HYPR_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/hypr}"
  local variables_file="${data_home}/variables.meta"

  [[ -f "${variables_file}" ]] || variables_file="${config_home}/variables.meta"

  printf '%s\n' \
    "${config_home}/userfonts.lua" \
    "${config_home}/themes/theme.meta" \
    "${variables_file}"
}

declare -gA HYPR_CONFIG_LAYER_CACHE=()
declare -g HYPR_CONFIG_LAYER_CACHE_KEY=""
declare -g HYPR_CONFIG_LAYER_CACHE_READY=0

hypr_config_file_signature_line() {
  local file_path="$1"

  if [[ -e "${file_path}" || -L "${file_path}" ]]; then
    stat -Lc '%n:%y:%s:%i' -- "${file_path}" 2>/dev/null || printf '%s:unreadable\n' "${file_path}"
  else
    printf '%s:missing\n' "${file_path}"
  fi
}

# shellcheck disable=SC2120
hypr_config_file_signature() {
  local file_path=""

  if (($#)); then
    for file_path in "$@"; do
      hypr_config_file_signature_line "${file_path}"
    done
    return 0
  fi

  while IFS= read -r file_path; do
    hypr_config_file_signature_line "${file_path}"
  done < <(hypr_config_layer_files)
}

hypr_config_parse_layer_file() {
  local file_path="$1"
  local -n layer_values_ref="$2"
  local raw_line=""
  local lhs=""
  local rhs=""
  local variable_key=""
  local lua_var_re='^[[:space:]]*vars\.set\("([^"]+)",[[:space:]]*"([^"]*)"\)'

  [[ -f "${file_path}" ]] || return 0
  if [[ ! -r "${file_path}" ]]; then
    printf 'ERROR: cannot read Hypr config file: %s\n' "${file_path}" >&2
    return 0
  fi

  while IFS= read -r raw_line; do
    [[ -n "${raw_line//[[:space:]]/}" ]] || continue
    [[ ! "${raw_line}" =~ ^[[:space:]]*# ]] || continue
    if [[ "${raw_line}" =~ ${lua_var_re} ]]; then
      variable_key="${BASH_REMATCH[1]}"
      rhs="${BASH_REMATCH[2]}"
      [[ -n "${rhs}" ]] || continue
      [[ -v "layer_values_ref[${variable_key}]" ]] && continue
      layer_values_ref["${variable_key}"]="${rhs}"
      continue
    fi
    [[ "${raw_line}" == *=* ]] || continue

    lhs="${raw_line%%=*}"
    rhs="${raw_line#*=}"
    lhs="${lhs#"${lhs%%[![:space:]]*}"}"
    lhs="${lhs%"${lhs##*[![:space:]]}"}"
    [[ "${lhs}" == \$* ]] || continue
    variable_key="${lhs#\$}"
    [[ -n "${variable_key}" ]] || continue

    rhs="${rhs%%#*}"
    rhs="${rhs#"${rhs%%[![:space:]]*}"}"
    rhs="${rhs%"${rhs##*[![:space:]]}"}"
    rhs="${rhs%\'}"
    rhs="${rhs#\'}"
    rhs="${rhs%\"}"
    rhs="${rhs#\"}"

    if [[ -z "${rhs}" ]]; then
      continue
    fi

    [[ -v "layer_values_ref[${variable_key}]" ]] && continue
    layer_values_ref["${variable_key}"]="${rhs}"
  done < "${file_path}"
}

hypr_config_layer_cache_load() {
  local cache_key=""
  local file_path=""

  # shellcheck disable=SC2119
  cache_key="$(hypr_config_file_signature)"
  if [[ "${HYPR_CONFIG_LAYER_CACHE_READY:-0}" -eq 1 && "${HYPR_CONFIG_LAYER_CACHE_KEY:-}" == "${cache_key}" ]]; then
    return 0
  fi

  HYPR_CONFIG_LAYER_CACHE=()
  while IFS= read -r file_path; do
    hypr_config_parse_layer_file "${file_path}" HYPR_CONFIG_LAYER_CACHE
  done < <(hypr_config_layer_files)

  HYPR_CONFIG_LAYER_CACHE_KEY="${cache_key}"
  HYPR_CONFIG_LAYER_CACHE_READY=1
}

hypr_config_value_from_layers() {
  local variable_key="${1#\$}"

  [[ -n "${variable_key}" ]] || return 1
  hypr_config_layer_cache_load || return 1
  [[ -v "HYPR_CONFIG_LAYER_CACHE[${variable_key}]" ]] || return 1
  printf '%s\n' "${HYPR_CONFIG_LAYER_CACHE[${variable_key}]}"

  return 0
}

hypr_border_metrics_into() {
  local border_name="${1:-}"
  local width_name="${2:-}"
  local metrics=""

  [[ -n "${border_name}" && -n "${width_name}" ]] || return 1
  command -v hyprctl >/dev/null 2>&1 || return 1
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 1

  local -n border_ref="${border_name}"
  local -n width_ref="${width_name}"

  border_ref=""
  width_ref=""
  metrics="$(hyprctl --batch -j 'getoption decoration:rounding;getoption general:border_size' 2>/dev/null | jq -sr '[(.[0].int // ""), (.[1].int // "")] | @tsv')" || return 1
  IFS=$'\t' read -r border_ref width_ref <<<"${metrics}"
  [[ "${border_ref}" =~ ^[0-9]+$ && "${width_ref}" =~ ^[0-9]+$ ]]
}

hypr_resolved_gaps_out() {
  local gaps_out="${hypr_gaps_out:-}"

  if [[ ! "${gaps_out}" =~ ^[0-9]+$ ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    gaps_out="$(
      if declare -F rofi_option_json >/dev/null 2>&1; then rofi_option_json general:gaps_out; else hyprctl -j getoption general:gaps_out 2>/dev/null; fi |
        jq -r '.int // ((.css // .custom // "") | split(" ")[0]) // empty' 2>/dev/null
    )"
  fi

  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out=5
  printf '%s\n' "${gaps_out}"
}

hypr_monitors_json() {
  if [[ -z "${HYPR_MONITORS_JSON_CACHE_READY:-}" ]]; then
    declare -g HYPR_MONITORS_JSON_CACHE_READY=1
    declare -g HYPR_MONITORS_JSON_CACHE
    HYPR_MONITORS_JSON_CACHE="$(hyprctl -j monitors all 2>/dev/null || true)"
  fi
  printf '%s\n' "${HYPR_MONITORS_JSON_CACHE}"
}

hypr_monitors_invalidate() {
  unset HYPR_MONITORS_JSON_CACHE_READY HYPR_MONITORS_JSON_CACHE ROFI_HYPR_SNAPSHOT_READY
}

hypr_monitor_geometry() {
  local selector="${1:-}"

  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  hypr_monitors_json \
    | jq -r --arg selector "${selector}" '
        (
          if $selector == "" then
            map(select(.focused == true))[0] // .[0]
          elif $selector | test("^[0-9]+$") then
            map(select((.id | tostring) == $selector))[0]
          else
            map(select(.name == $selector))[0]
          end
        ) as $monitor | select($monitor != null)
        | (($monitor.scale // 1) | if . > 0 then . else 1 end) as $scale
        | [
            ((($monitor.x // 0) / $scale | trunc) + 0),
            ((($monitor.y // 0) / $scale | trunc) + 0),
            ((($monitor.width // 0) / $scale | trunc) + 0),
            ((($monitor.height // 0) / $scale | trunc) + 0),
            ($monitor.reserved[0] // 0),
            ($monitor.reserved[1] // 0),
            ($monitor.reserved[2] // 0),
            ($monitor.reserved[3] // 0)
          ]
        | @tsv
      '
}

hypr_focused_monitor_geometry() {
  hypr_monitor_geometry
}

hypr_window_edge_padding_px() {
  local gaps_out=5
  local ignored_border=""
  local border_width=2

  gaps_out="$(hypr_resolved_gaps_out 2>/dev/null || true)"
  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out=5

  border_width="${hypr_width:-${HYPR_RUNTIME_BORDER_WIDTH:-${HYPR_BORDER_WIDTH:-}}}"
  if [[ ! "${border_width}" =~ ^[0-9]+$ ]]; then
    if declare -F rofi_option_json >/dev/null 2>&1; then
      border_width="$(rofi_option_json general:border_size | jq -r '.int // empty' 2>/dev/null || true)"
    else
      hypr_border_metrics_into ignored_border border_width 2>/dev/null || true
    fi
  fi
  [[ "${border_width}" =~ ^[0-9]+$ ]] || border_width=2

  printf '%s\n' "$((gaps_out * 2 + border_width))"
}

hypr_lua_string() {
  hypr_lua_quote "${1-}"
}

hypr_compact_path() {
  local path="$1"
  local var_name=""
  local base_path=""

  for var_name in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME HOME; do
    base_path="${!var_name:-}"
    [[ -n "${base_path}" && "${path}" == "${base_path}"/* ]] || continue
    printf '$%s%s\n' "${var_name}" "${path#"${base_path}"}"
    return 0
  done

  printf '%s\n' "${path}"
}
