#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Print usage text and exit 0 when -h/--help appears before a `--` terminator.
# Usage: hypr_help_guard "<usage text>" "$@"
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

# --- Init-system abstraction (systemd / runit) -----------------------------
# Lets the same config drive a systemd user session or a runit (Artix) one.
# Detection is cached per-process in HYPR_INIT_SYSTEM. Override for testing by
# exporting HYPR_INIT_SYSTEM=systemd|runit|other before invoking.

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

# True only when a usable systemd --user instance is reachable.
hypr_systemd_user_ok() {
  [[ "$(hypr_init_system)" == "systemd" ]] || return 1
  systemctl --user is-active default.target >/dev/null 2>&1
}

# Directory holding per-user runit service definitions.
hypr_user_sv_dir() {
  printf '%s\n' "${HYPR_USER_SV_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sv}"
}

# svc_user <start|stop|restart|is-active> <service-name>
# Dispatches a user-service lifecycle op to the active init system. The name is
# given without a suffix; the systemd path appends .service, the runit path uses
# it as the sv service directory name. Returns success best-effort; is-active
# returns the real running state. No supervisor -> lifecycle ops are no-ops.
hypr_svc_user() {
  local action="${1:-}" name="${2:-}"
  [[ -n "${action}" && -n "${name}" ]] || return 2

  case "$(hypr_init_system)" in
    systemd)
      local unit="${name%.service}.service"
      case "${action}" in
        start)     systemctl --user start --no-block "${unit}" >/dev/null 2>&1 ;;
        stop)      systemctl --user stop "${unit}" >/dev/null 2>&1 ;;
        restart)   systemctl --user restart "${unit}" >/dev/null 2>&1 ;;
        is-active) systemctl --user is-active --quiet "${unit}" >/dev/null 2>&1 ;;
        *) return 2 ;;
      esac
      ;;
    runit)
      command -v sv >/dev/null 2>&1 || return 1
      local svc="${name%.service}"
      local sv_dir; sv_dir="$(hypr_user_sv_dir)"
      case "${action}" in
        start)     SVDIR="${sv_dir}" sv up "${svc}" >/dev/null 2>&1 ;;
        stop)      SVDIR="${sv_dir}" sv down "${svc}" >/dev/null 2>&1 ;;
        restart)   SVDIR="${sv_dir}" sv restart "${svc}" >/dev/null 2>&1 ;;
        is-active) SVDIR="${sv_dir}" sv status "${svc}" 2>/dev/null | grep -q '^run:' ;;
        *) return 2 ;;
      esac
      ;;
    *)
      [[ "${action}" == "is-active" ]] && return 1
      return 0
      ;;
  esac
}

# svc_user_signal <service-name> <SIGNAL>
# Sends a signal to a running user service (e.g. USR2 to reload). Maps the
# common signals to runit's sv control subcommands.
hypr_svc_user_signal() {
  local name="${1:-}" sig="${2:-}"
  [[ -n "${name}" && -n "${sig}" ]] || return 2

  case "$(hypr_init_system)" in
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

# Native Hyprland 0.55 Lua IPC helpers.
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

hypr_user_uid() {
  printf '%s\n' "${UID:-$(id -u)}"
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

hypr_runtime_root_dir() {
  local user_uid=""
  local runtime_dir=""
  local fallback_dir=""

  user_uid="$(hypr_user_uid)" || return 1
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/${user_uid}}"
  if [[ -n "${runtime_dir}" ]] && mkdir -p "${runtime_dir}" 2>/dev/null; then
    printf '%s\n' "${runtime_dir}"
    return 0
  fi

  fallback_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/runtime"
  mkdir -p "${fallback_dir}" || return 1
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
    # Prefer shared path as canonical target for new writes/read attempts.
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

hypr_trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

hypr_config_file_signature_line() {
  local file_path="$1"

  if [[ -e "${file_path}" || -L "${file_path}" ]]; then
    stat -Lc '%n:%y:%s:%i' -- "${file_path}" 2>/dev/null || printf '%s:unreadable\n' "${file_path}"
  else
    printf '%s:missing\n' "${file_path}"
  fi
}

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

# Existing keys are kept, so calling this per file in layer order preserves
# first-definition-wins.
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
    lhs="$(hypr_trim_whitespace "${lhs}")"
    [[ "${lhs}" == \$* ]] || continue
    variable_key="${lhs#\$}"
    [[ -n "${variable_key}" ]] || continue

    rhs="${rhs%%#*}"
    rhs="$(hypr_trim_whitespace "${rhs}")"
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
  local metrics_dir=""
  local metrics_file=""
  local line=""
  local -a ints=()

  [[ -n "${border_name}" && -n "${width_name}" ]] || return 1
  command -v hyprctl >/dev/null 2>&1 || return 1
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 1

  local -n border_ref="${border_name}"
  local -n width_ref="${width_name}"

  border_ref=""
  width_ref=""
  metrics_dir="$(hypr_runtime_subdir hypr)" || return 1
  metrics_file="${metrics_dir}/hypr-border-metrics.$$.$RANDOM"

  if ! hyprctl --batch "getoption decoration:rounding;getoption general:border_size" >"${metrics_file}" 2>/dev/null; then
    rm -f -- "${metrics_file}"
    return 1
  fi

  while IFS= read -r line; do
    [[ "${line}" =~ ^int:\ ([0-9]+)$ ]] || continue
    ints+=("${BASH_REMATCH[1]}")
    (( ${#ints[@]} >= 2 )) && break
  done < "${metrics_file}"

  rm -f -- "${metrics_file}"
  (( ${#ints[@]} >= 2 )) || return 1

  border_ref="${ints[0]}"
  width_ref="${ints[1]}"
}

hypr_resolved_gaps_out() {
  local gaps_out="${hypr_gaps_out:-}"

  if [[ ! "${gaps_out}" =~ ^[0-9]+$ ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    gaps_out="$(
      hyprctl -j getoption general:gaps_out 2>/dev/null |
        jq -r '.int // ((.css // .custom // "") | split(" ")[0]) // empty' 2>/dev/null
    )"
  fi

  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out=5
  printf '%s\n' "${gaps_out}"
}

hypr_focused_monitor_geometry() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  hyprctl -j monitors \
    | jq -r '
        (map(select(.focused == true))[0] // .[0]) as $monitor
        | [
            ($monitor.x // 0),
            ($monitor.y // 0),
            ($monitor.width // 0),
            ($monitor.height // 0),
            ($monitor.scale // 1),
            ($monitor.reserved[0] // 0),
            ($monitor.reserved[1] // 0),
            ($monitor.reserved[2] // 0),
            ($monitor.reserved[3] // 0)
          ]
        | @tsv
      ' \
    | awk -F '\t' '{ scale = ($5 > 0 ? $5 : 1); printf "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", $1 / scale, $2 / scale, $3 / scale, $4 / scale, $6, $7, $8, $9 }'
}

hypr_window_edge_padding_px() {
  local gaps_out=5
  local ignored_border=""
  local border_width=2

  gaps_out="$(hypr_resolved_gaps_out 2>/dev/null || true)"
  [[ "${gaps_out}" =~ ^[0-9]+$ ]] || gaps_out=5

  border_width="${hypr_width:-${HYPR_RUNTIME_BORDER_WIDTH:-${HYPR_BORDER_WIDTH:-}}}"
  if [[ ! "${border_width}" =~ ^[0-9]+$ ]]; then
    hypr_border_metrics_into ignored_border border_width 2>/dev/null || true
  fi
  [[ "${border_width}" =~ ^[0-9]+$ ]] || border_width=2

  printf '%s\n' "$((gaps_out * 2 + border_width))"
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
