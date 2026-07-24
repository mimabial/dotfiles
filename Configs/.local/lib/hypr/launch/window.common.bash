#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

launch_source_core_common() {
  local core_common="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh"

  if declare -F hypr_monitor_geometry >/dev/null 2>&1 \
    && declare -F hypr_focused_monitor_geometry >/dev/null 2>&1 \
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

  launch_source_core_common || return 1

  if [[ "${use_empty_workspace}" -eq 1 ]]; then
    IFS=$'\t' read -r active_workspace has_other_window \
      < <(launch_active_workspace_occupancy "${exclude_address}") || return 1
    [[ -n "${active_workspace}" ]] || return 1

    if [[ "${has_other_window}" == "true" ]]; then
      hypr_lua_dispatch 'hl.dsp.focus({workspace="empty"})' >/dev/null 2>&1 || return 1
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
  hypr_monitor_geometry
}

launch_monitor_geometry() {
  local monitor_selector="${1:-}"

  launch_source_core_common || return 1
  hypr_monitor_geometry "${monitor_selector}"
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

launch_window_profile_file() {
  printf '%s\n' "${HYPR_WINDOW_PROFILE_FILE:-${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/window_profiles.lua}"
}

launch_geometry_profile_specs() {
  local profile_name="$1"
  local profile_file=""

  profile_file="$(launch_window_profile_file)"
  [[ -r "${profile_file}" ]] || {
    printf 'Window profile file not found: %s\n' "${profile_file}" >&2
    return 1
  }
  command -v lua >/dev/null 2>&1 || {
    printf 'lua is required to read window profiles\n' >&2
    return 1
  }

  HYPR_WINDOW_PROFILE_FILE="${profile_file}" HYPR_WINDOW_PROFILE_NAME="${profile_name}" lua -e '
    local profile_file = assert(os.getenv("HYPR_WINDOW_PROFILE_FILE"))
    local profile_name = assert(os.getenv("HYPR_WINDOW_PROFILE_NAME"))
    local profiles = assert(loadfile(profile_file))()
    local profile = profiles[profile_name]
    assert(type(profile) == "table", "unknown window profile: " .. profile_name)
    assert(type(profile.width) == "string" and profile.width:match("^%d+%%?$"), "invalid profile width")
    assert(type(profile.height) == "string" and profile.height:match("^%d+%%?$"), "invalid profile height")
    assert(profile.basis == "monitor" or profile.basis == "usable", "invalid profile basis")
    io.write(profile.width, "\t", profile.height, "\t", profile.basis, "\n")
  '
}

launch_monitor_usable_geometry() {
  local monitor_selector="${1:-}"
  local monitor_x=""
  local monitor_y=""
  local monitor_width=""
  local monitor_height=""
  local reserve_left=""
  local reserve_top=""
  local reserve_right=""
  local reserve_bottom=""
  local visible_width=""
  local visible_height=""
  local edge_padding=""

  IFS=$'\t' read -r monitor_x monitor_y monitor_width monitor_height reserve_left reserve_top reserve_right reserve_bottom \
    <<<"$(launch_monitor_geometry "${monitor_selector}")"

  visible_width=$((monitor_width - reserve_left - reserve_right))
  visible_height=$((monitor_height - reserve_top - reserve_bottom))
  ((visible_width > 0 && visible_height > 0)) || return 1

  edge_padding="$(launch_window_edge_padding_px)"

  local padded_width=$((visible_width - (edge_padding * 2)))
  local padded_height=$((visible_height - (edge_padding * 2)))
  local usable_x=$((monitor_x + reserve_left + edge_padding))
  local usable_y=$((monitor_y + reserve_top + edge_padding))
  local usable_width=$((monitor_width - reserve_left - reserve_right - (edge_padding * 2)))
  local usable_height=$((monitor_height - reserve_top - reserve_bottom - (edge_padding * 2)))

  ((padded_width > 0)) || padded_width=1
  ((padded_height > 0)) || padded_height=1
  ((usable_width > 0)) || usable_width=1
  ((usable_height > 0)) || usable_height=1

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${padded_width}" \
    "${padded_height}" \
    "${usable_x}" \
    "${usable_y}" \
    "${usable_width}" \
    "${usable_height}"
}

launch_resolve_geometry_profile() {
  local profile_name="$1"
  local monitor_selector="${2:-}"
  local width_spec=""
  local height_spec=""
  local basis=""
  local base_width=""
  local base_height=""
  local ignored=""

  IFS=$'\t' read -r width_spec height_spec basis <<<"$(launch_geometry_profile_specs "${profile_name}")" || return 1
  if [[ "${basis}" == "usable" ]]; then
    IFS=$'\t' read -r base_width base_height ignored ignored ignored ignored \
      <<<"$(launch_monitor_usable_geometry "${monitor_selector}")" || return 1
  else
    IFS=$'\t' read -r ignored ignored base_width base_height ignored ignored ignored ignored \
      <<<"$(launch_monitor_geometry "${monitor_selector}")" || return 1
  fi

  printf '%s\t%s\n' \
    "$(launch_resolve_dimension "${width_spec}" "${base_width}")" \
    "$(launch_resolve_dimension "${height_spec}" "${base_height}")"
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
