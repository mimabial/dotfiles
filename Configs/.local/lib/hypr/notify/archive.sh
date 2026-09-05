#!/usr/bin/env bash
# The store behind the notification panel.
#
# dunst keeps 20 notifications in memory (history_length) and drops the rest,
# and the whole ring dies with the daemon. The [notification_archive] rule in
# dunst.conf runs `add` for every notification as it is displayed; this copies
# it out, with any picture it carried, and keeps it until retention says
# otherwise.
#
# Every subcommand prints JSON, including failures, so nothing that goes wrong
# reaches the panel as a parse error.
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

usage() {
  cat <<'USAGE'
Usage: hyprshell notify/archive <command> [args]

  add                 archive the notification in the DUNST_* environment
  list [LIMIT]        the archive as JSON, newest first (default 200)
  remove KEY          drop one entry and any picture kept for it
  clear               drop all of them
  seen [MS]           read or set when the panel was last opened
  unread              how many arrived since then
  prune               apply the retention limits now

Retention and exclusions come from staterc:
  NOTIFY_KEEP_DAYS          days to keep         (default 30)
  NOTIFY_MAX_ITEMS          ceiling regardless   (default 1000)
  NOTIFY_ARCHIVE_SKIP_APPS  '|'-separated app names
  NOTIFY_ARCHIVE_SKIP_TAGS  '|'-separated stack tags
USAGE
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

hypr_runtime_require state >/dev/null 2>&1 || true

store="${HYPR_STATE_HOME}/notifications"
archive="${store}/archive.jsonl"
images="${store}/images"
seen_file="${store}/seen"

# Everything here is a record of what you were sent, so none of it is readable
# by anyone else on the machine.
ensure_store() {
  mkdir -p "${images}"
  chmod 700 "${store}" "${images}" 2>/dev/null || true
  [[ -e "${archive}" ]] || : >"${archive}"
  [[ -e "${seen_file}" ]] || printf '0\n' >"${seen_file}"
  chmod 600 "${archive}" "${seen_file}" 2>/dev/null || true
}

# The lock is taken in a subshell so a descriptor is never held past one call.
with_lock() {
  local lock_file=""
  lock_file="$(hypr_lock_path notify_archive 2>/dev/null)" || lock_file="${store}/.lock"
  (
    exec 9>"${lock_file}"
    flock 9
    "$@"
  )
}

setting() { state_get "$1" "$2" 2>/dev/null || printf '%s\n' "$2"; }
now_ms() { printf '%s' "$(($(date +%s%N) / 1000000))"; }

# dunst resolves DUNST_ICON_PATH to an absolute path either way: a themed name
# lands under an icon theme root, a path the sender chose does not. That
# boundary separates the sending app's icon from the picture the notification is
# about — a screenshot, album art, a wallpaper thumbnail — and only the second is
# worth copying, because the sender's file can move or be deleted while a themed
# icon is package-owned and stays put.
is_themed_icon() {
  local path="$1" root=""
  for root in \
    "${XDG_DATA_HOME:-$HOME/.local/share}/icons" \
    "$HOME/.icons" \
    /usr/share/icons \
    /usr/share/pixmaps; do
    [[ "${path}" == "${root}/"* ]] && return 0
  done
  return 1
}

# Only files that really are images come into the store, and the copy is named
# by content so the same picture arriving twice is kept once.
copy_image() {
  local src="$1" mime="" ext="" hash="" dest=""

  [[ -f "${src}" && -r "${src}" ]] || return 1
  (($(stat -c %s -- "${src}" 2>/dev/null || echo 0) <= 12582912)) || return 1
  mime="$(file --brief --mime-type -- "${src}" 2>/dev/null || true)"
  [[ "${mime}" == image/* ]] || return 1

  case "${mime}" in
    image/png) ext="png" ;;
    image/jpeg) ext="jpg" ;;
    image/gif) ext="gif" ;;
    image/webp) ext="webp" ;;
    image/svg+xml) ext="svg" ;;
    *) ext="img" ;;
  esac

  hash="$("${HYPR_HASH_COMMAND:-xxh64sum}" <"${src}" 2>/dev/null | awk '{print $1}')"
  [[ -n "${hash}" ]] || return 1

  dest="${images}/${hash}.${ext}"
  if [[ ! -f "${dest}" ]]; then
    # A screenshot or wallpaper arrives at full size, and the panel shows it a
    # few hundred pixels wide. Scaling on the way in is the difference between
    # megabytes an entry and kilobytes; `>` means a small icon is left alone.
    if [[ "${ext}" != "svg" ]] && command -v magick >/dev/null 2>&1; then
      magick "${src}" -auto-orient -resize '640x640>' -strip "${dest}" 2>/dev/null \
        || cp -- "${src}" "${dest}" 2>/dev/null || return 1
    else
      cp -- "${src}" "${dest}" 2>/dev/null || return 1
    fi
    chmod 600 "${dest}" 2>/dev/null || true
  fi
  printf '%s\n' "${dest}"
}

# dunst cannot express these itself: an empty `script` in a rule is dropped
# rather than clearing an earlier one, and its regexes are POSIX (no negative
# lookahead), so the apps and tags dunst is told to keep out of history are
# named here instead. Transient notifications are excluded by the rule itself.
is_skipped() {
  local app="$1" tag="$2" entry=""
  local -a skip=()

  IFS='|' read -ra skip <<<"$(setting NOTIFY_ARCHIVE_SKIP_APPS 'Claude Code')"
  for entry in "${skip[@]}"; do
    [[ -n "${entry}" && "${app}" == "${entry}" ]] && return 0
  done
  IFS='|' read -ra skip <<<"$(setting NOTIFY_ARCHIVE_SKIP_TAGS 'submap-hint')"
  for entry in "${skip[@]}"; do
    [[ -n "${entry}" && "${tag}" == "${entry}" ]] && return 0
  done
  return 1
}

cmd_add() {
  local app="${DUNST_APP_NAME:-}" summary="${DUNST_SUMMARY:-}" body="${DUNST_BODY:-}"
  local urgency="${DUNST_URGENCY:-NORMAL}" category="${DUNST_CATEGORY:-}"
  local desktop="${DUNST_DESKTOP_ENTRY:-}" source_icon="${DUNST_ICON_PATH:-}"
  local id="${DUNST_ID:-0}" tag="${DUNST_STACK_TAG:-}"
  local icon="" preview="" stamp="" key=""

  [[ -n "${summary}${body}" ]] || return 0
  is_skipped "${app}" "${tag}" && return 0

  if [[ -n "${source_icon}" && -f "${source_icon}" ]]; then
    if is_themed_icon "${source_icon}"; then
      icon="${source_icon}"
    else
      icon="$(copy_image "${source_icon}" || true)"
      preview="${icon}"
    fi
  fi

  stamp="$(now_ms)"
  [[ "${id}" =~ ^[0-9]+$ ]] || id=0
  key="${stamp}-${id}"

  ensure_store
  with_lock append_entry \
    "${key}" "${stamp}" "${app}" "${summary}" "${body}" \
    "${urgency}" "${category}" "${desktop}" "${icon}" "${preview}"
}

append_entry() {
  jq -cn \
    --arg key "$1" --argjson ts "$2" --arg app "$3" --arg summary "$4" \
    --arg body "$5" --arg urgency "$6" --arg category "$7" \
    --arg desktop "$8" --arg icon "$9" --arg preview "${10}" \
    '{key: $key, ts: $ts, app: $app, summary: $summary, body: $body,
      urgency: $urgency, category: $category, desktop: $desktop,
      icon: $icon, preview: $preview}' >>"${archive}"
  prune_locked
}

# Reads all go through `fromjson?`: one malformed line is dropped rather than
# taking the whole archive down with it.
prune_locked() {
  local cutoff="" keep_days="" max_items="" before="" after="" tmp=""

  keep_days="$(setting NOTIFY_KEEP_DAYS 30)"
  max_items="$(setting NOTIFY_MAX_ITEMS 1000)"
  [[ "${keep_days}" =~ ^[0-9]+$ ]] || keep_days=30
  [[ "${max_items}" =~ ^[0-9]+$ ]] && ((max_items > 0)) || max_items=1000
  cutoff=$(($(now_ms) - keep_days * 86400000))

  before="$(wc -l <"${archive}" 2>/dev/null || echo 0)"
  tmp="${archive}.tmp"
  jq -Rnr --argjson cutoff "${cutoff}" --argjson max "${max_items}" \
    '[inputs | fromjson? | select(.ts >= $cutoff)] | .[-$max:] | .[] | tojson' \
    <"${archive}" >"${tmp}" || {
    rm -f -- "${tmp}"
    return 0
  }
  mv -- "${tmp}" "${archive}"
  chmod 600 "${archive}" 2>/dev/null || true

  after="$(wc -l <"${archive}" 2>/dev/null || echo 0)"
  ((after < before)) && sweep_images
  return 0
}

# Pictures outlive the entry that named them otherwise; a themed icon path is
# never inside the store, so it simply matches nothing here.
sweep_images() {
  local kept="" file=""
  kept="$(jq -Rnr '[inputs | fromjson? | .icon, .preview]
                   | .[] | select(type == "string" and . != "")' \
    <"${archive}" | sort -u)"
  for file in "${images}"/*; do
    [[ -f "${file}" ]] || continue
    grep -qxF -- "${file}" <<<"${kept}" || rm -f -- "${file}"
  done
}

cmd_list() {
  local limit="${1:-200}"
  [[ "${limit}" =~ ^[0-9]+$ ]] || limit=200
  ensure_store
  jq -Rcn --argjson limit "${limit}" \
    '[inputs | fromjson?] | reverse | .[:$limit]' <"${archive}" 2>/dev/null \
    || printf '[]\n'
}

cmd_remove() {
  local key="$1"
  [[ -n "${key}" ]] || {
    printf '{"ok":false,"error":"missing key"}\n'
    return 1
  }
  ensure_store
  with_lock remove_locked "${key}"
  printf '{"ok":true,"removed":%s}\n' "$(jq -Rn --arg k "${key}" '$k')"
}

remove_locked() {
  local tmp="${archive}.tmp"
  jq -Rnr --arg key "$1" \
    'inputs | fromjson? | select(.key != $key) | tojson' \
    <"${archive}" >"${tmp}" && mv -- "${tmp}" "${archive}"
  chmod 600 "${archive}" 2>/dev/null || true
  sweep_images
}

cmd_clear() {
  ensure_store
  with_lock clear_locked
  printf '{"ok":true,"cleared":true}\n'
}

clear_locked() {
  : >"${archive}"
  chmod 600 "${archive}" 2>/dev/null || true
  rm -f -- "${images:?}"/* 2>/dev/null || true
}

cmd_seen() {
  ensure_store
  if [[ -n "${1:-}" ]]; then
    [[ "$1" =~ ^[0-9]+$ ]] || {
      printf '{"ok":false,"error":"not a timestamp"}\n'
      return 1
    }
    printf '%s\n' "$1" >"${seen_file}"
    chmod 600 "${seen_file}" 2>/dev/null || true
  fi
  printf '{"ok":true,"seen":%s}\n' "$(read_seen)"
}

read_seen() {
  local value=""
  value="$(cat -- "${seen_file}" 2>/dev/null || echo 0)"
  [[ "${value}" =~ ^[0-9]+$ ]] || value=0
  printf '%s' "${value}"
}

cmd_unread() {
  ensure_store
  printf '{"ok":true,"unread":%s}\n' \
    "$(jq -Rn --argjson seen "$(read_seen)" \
      '[inputs | fromjson? | select(.ts > $seen)] | length' <"${archive}")"
}

case "${1:-}" in
  add)
    shift
    cmd_add
    ;;
  list)
    shift
    cmd_list "${1:-200}"
    ;;
  remove)
    shift
    cmd_remove "${1:-}"
    ;;
  clear)
    shift
    cmd_clear
    ;;
  seen)
    shift
    cmd_seen "${1:-}"
    ;;
  unread)
    shift
    cmd_unread
    ;;
  prune)
    shift
    ensure_store
    with_lock prune_locked
    printf '{"ok":true,"pruned":true}\n'
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
