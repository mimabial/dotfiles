launch_regex_escape() {
  printf '%s\n' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

launch_resolve_window_address() {
  local window_pattern="$1"
  local clients_json="${2:-}"
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

  [[ -n "${clients_json}" ]] || clients_json="$(hyprctl clients -j)"
  printf '%s\n' "${clients_json}" \
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

launch_print_window_address() {
  local address=""
  address="$(launch_resolve_window_address "$1")"
  [[ -n "${address}" ]] && printf '%s\n' "${address}"
}

launch_wait_for_window_address() {
  launch_source_core_common || return 1
  hypr_wait_for 20 '@(openwindow|windowtitlev2)>>*' launch_print_window_address "$1"
}
