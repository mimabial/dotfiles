#!/bin/bash

launch_source_core_common() {
  local core_common="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh"

  if declare -F hypr_focused_monitor_geometry >/dev/null 2>&1 \
    && declare -F hypr_window_edge_padding_px >/dev/null 2>&1; then
    return 0
  fi

  [[ -r "${core_common}" ]] || return 1
  # shellcheck source=/dev/null
  source "${core_common}"
}

launch_resolve_window_address() {
  local window_pattern="$1"

  hyprctl clients -j \
    | jq -r --arg p "$window_pattern" '.[] | select((.class | test("\\b" + $p + "\\b"; "i")) or (.title | test("\\b" + $p + "\\b"; "i"))) | .address' \
    | head -n1
}

launch_read_window_info() {
  local window_address="$1"

  hyprctl clients -j \
    | jq -r --arg a "$window_address" '.[] | select(.address == $a) | [.size[0], .size[1], .floating, .workspace.name] | @tsv' \
    | head -n1
}

launch_wait_for_window_info_stable() {
  local window_address="$1"
  local attempts="${2:-30}"
  local stable_reads_required="${3:-3}"
  local info=""
  local last_info=""
  local stable_reads=0

  while ((attempts > 0)); do
    info="$(launch_read_window_info "${window_address}")"
    [[ -n "${info}" ]] || return 1

    if [[ "${info}" == "${last_info}" ]]; then
      stable_reads=$((stable_reads + 1))
      if ((stable_reads >= stable_reads_required)); then
        printf '%s\n' "${info}"
        return 0
      fi
    else
      last_info="${info}"
      stable_reads=1
    fi

    sleep 0.05
    attempts=$((attempts - 1))
  done

  [[ -n "${last_info}" ]] || return 1
  printf '%s\n' "${last_info}"
}

launch_focused_workspace_name() {
  hyprctl activeworkspace -j | jq -r '.name // empty'
}

launch_prepare_target_workspace() {
  local use_empty_workspace="$1"
  local exclude_address="${2:-}"
  local active_workspace=""

  active_workspace="$(launch_focused_workspace_name)"
  [[ -n "${active_workspace}" ]] || return 1

  if [[ "${use_empty_workspace}" -eq 1 ]] && launch_workspace_has_other_window "${active_workspace}" "${exclude_address}"; then
    hyprctl dispatch workspace empty >/dev/null 2>&1 || return 1
    active_workspace="$(launch_focused_workspace_name)"
    [[ -n "${active_workspace}" ]] || return 1
  fi

  printf '%s\n' "${active_workspace}"
}

launch_workspace_has_other_window() {
  local workspace_name="$1"
  local exclude_address="${2:-}"

  [[ -n "${workspace_name}" ]] || return 1

  hyprctl clients -j \
    | jq -e --arg ws "${workspace_name}" --arg exclude "${exclude_address}" '
        .[]
        | select(.workspace.name == $ws)
        | select(.address != $exclude)
      ' \
    >/dev/null 2>&1
}

launch_focused_monitor_geometry() {
  launch_source_core_common || return 1
  hypr_focused_monitor_geometry
}

launch_resolve_dimension() {
  local spec="$1"
  local base="$2"
  local percent=""

  case "${spec}" in
    *%)
      percent="${spec%%%}"
      [[ "${percent}" =~ ^[0-9]+$ ]] || return 1
      printf '%s\n' $((base * percent / 100))
      ;;
    *)
      [[ "${spec}" =~ ^[0-9]+$ ]] || return 1
      printf '%s\n' "${spec}"
      ;;
  esac
}

launch_window_edge_padding_px() {
  launch_source_core_common || return 1
  hypr_window_edge_padding_px
}

launch_wait_for_window_address() {
  local window_pattern="$1"
  local attempts=100
  local address=""

  while ((attempts > 0)); do
    address="$(launch_resolve_window_address "$window_pattern")"
    [[ -n "${address}" ]] && {
      printf '%s\n' "${address}"
      return 0
    }
    sleep 0.05
    attempts=$((attempts - 1))
  done

  return 1
}
