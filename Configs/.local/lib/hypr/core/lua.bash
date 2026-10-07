#!/usr/bin/env bash

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
