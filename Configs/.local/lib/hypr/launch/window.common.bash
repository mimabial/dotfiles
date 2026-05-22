#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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

launch_regex_escape() {
  printf '%s\n' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

launch_resolve_window_address() {
  local window_pattern="$1"
  local selector_kind="any"
  local escaped_pattern=""

  case "${window_pattern}" in
    class:*)
      selector_kind="class"
      window_pattern="${window_pattern#class:}"
      ;;
    title:*)
      selector_kind="title"
      window_pattern="${window_pattern#title:}"
      ;;
  esac

  escaped_pattern="$(launch_regex_escape "${window_pattern}")"

  hyprctl clients -j \
    | jq -r --arg p "${window_pattern}" --arg re "${escaped_pattern}" --arg kind "${selector_kind}" '
        def word_match($value; $re):
          (($value // "") | test("\\b" + $re + "\\b"; "i"));
        def exact_class($p):
          ((.class // "" | ascii_downcase) == ($p | ascii_downcase))
          or ((.initialClass // "" | ascii_downcase) == ($p | ascii_downcase));
        def class_match($re):
          word_match(.class; $re) or word_match(.initialClass; $re);
        def title_match($re):
          word_match(.title; $re) or word_match(.initialTitle; $re);

        [
          .[]
          | if $kind == "class" then
              select(exact_class($p) or class_match($re)) | . + {_rank: 0}
            elif $kind == "title" then
              select(title_match($re)) | . + {_rank: 0}
            elif exact_class($p) then
              . + {_rank: 0}
            elif class_match($re) then
              . + {_rank: 1}
            elif title_match($re) then
              . + {_rank: 2}
            else
              empty
            end
        ]
        | sort_by(._rank)
        | .[0].address // empty
      '
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

launch_active_workspace_occupancy() {
  local exclude_address="${1:-}"

  hyprctl --batch -j "activeworkspace;clients" \
    | jq -sr --arg exclude "${exclude_address}" '
        .[0].name as $workspace_name
        | [
            $workspace_name,
            (
              (.[1] // [])
              | any(.[]; .workspace.name == $workspace_name and .address != $exclude)
            )
          ]
        | @tsv
      '
}

launch_prepare_target_workspace() {
  local use_empty_workspace="$1"
  local exclude_address="${2:-}"
  local active_workspace=""
  local has_other_window="false"

  if [[ "${use_empty_workspace}" -eq 1 ]]; then
    IFS=$'\t' read -r active_workspace has_other_window \
      < <(launch_active_workspace_occupancy "${exclude_address}") || return 1
    [[ -n "${active_workspace}" ]] || return 1

    if [[ "${has_other_window}" == "true" ]]; then
      hyprctl dispatch workspace empty >/dev/null 2>&1 || return 1
      active_workspace="$(launch_focused_workspace_name)"
      [[ -n "${active_workspace}" ]] || return 1
    fi
  else
    active_workspace="$(launch_focused_workspace_name)"
    [[ -n "${active_workspace}" ]] || return 1
  fi

  printf '%s\n' "${active_workspace}"
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
  local attempts="${2:-${HYPR_LAUNCH_WAIT_ATTEMPTS:-400}}"
  local address=""

  [[ "${attempts}" =~ ^[0-9]+$ ]] || attempts=400

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
