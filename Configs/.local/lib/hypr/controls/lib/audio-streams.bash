PIPEWIRE_FOLLOW_DEFAULT_TARGET=-1

get_default_source_target() {
  local default_source=""

  default_source="$(pactl get-default-source 2>/dev/null || true)"
  if [[ -n "${default_source}" && "${default_source}" != *.monitor ]]; then
    printf '%s\n' "${default_source}"
    return 0
  fi
  pactl list short sources 2>/dev/null | awk '$2 !~ /\.monitor$/ {print $2; exit}'
}

source_volume_pct() {
  local target="$1"
  pactl get-source-volume "${target}" 2>/dev/null | awk 'match($0,/[0-9]+%/){print substr($0,RSTART,RLENGTH-1); exit}'
}

source_is_muted() {
  local target="$1"
  [[ "$(pactl get-source-mute "${target}" 2>/dev/null)" == *yes ]]
}

streams_with_explicit_target() {
  sed -n "s/^update: id:\([0-9][0-9]*\) key:'target\.\(object\|node\)' value:'\([^']*\)'.*/\1\t\3/p" |
    awk -F '\t' -v follow_default="${PIPEWIRE_FOLLOW_DEFAULT_TARGET}" '$2 != follow_default { print $1 }'
}
