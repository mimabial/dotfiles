#!/usr/bin/env bash
set -euo pipefail

WALLPAPER_DIR="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)"

# `! cmd` cannot fail a suite: set -e is suppressed for a negated command.
refute() {
  if "$@"; then
    printf 'expected failure: %s\n' "$*" >&2
    exit 1
  fi
}

test_parser() (
  wallpaper_show_help() { exit 90; }
  source "${WALLPAPER_DIR}/lib/arguments.bash"
  wallpaper_parse_arguments --backend hyprlock -Gn
  [[ "${wallpaper_action}:${wallpaper_backend}:${wallpaper_is_global}" == next:hyprlock:true ]]
  refute bash -c 'source "$1"; wallpaper_parse_arguments next --set /tmp/wall' bash "${WALLPAPER_DIR}/lib/arguments.bash" 2>/dev/null
)

test_actions() (
  print_log() { :; }
  source "${WALLPAPER_DIR}/lib/command-policy.bash"
  source "${WALLPAPER_DIR}/lib/commands.bash"
  local action
  for action in next previous random set resume display notify select start link get output clean json; do
    wallpaper_action="${action}"
    wallpaper_wait_for_lock=0
    wallpaper_configure_action
    declare -F "${wallpaper_action_handler}" >/dev/null
  done
)

test_json() (
  LIB_DIR="${WALLPAPER_DIR%/hypr/wallpaper}"
  source "${WALLPAPER_DIR}/lib/catalog-json.bash"
  wallpaper_paths=("/tmp/a b.jpg" "/tmp/東京.png")
  declare -A wallpaper_hash_by_path=(["${wallpaper_paths[0]}"]=abc ["${wallpaper_paths[1]}"]=def)
  wallpaper_catalog_build_json /tmp |
    jq -e 'length == 2 and .[0].hash == "abc" and .[1].hash == "def"' >/dev/null
)

test_json_cache_freshness() (
  source "${WALLPAPER_DIR}/lib/catalog-json.bash"
  local dir
  dir="$(mktemp -d)"; trap 'rm -rf -- "${dir}"' EXIT
  printf 'cached\n' >"${dir}/catalog.json"
  : >"${dir}/hashmap.tsv"
  touch -d '@1000.100000000' "${dir}/catalog.json"
  touch -d '@1000.200000000' "${dir}/hashmap.tsv"
  refute wallpaper_catalog_print_cached_json_if_current "${dir}/catalog.json" "${dir}/hashmap.tsv"
  touch -d '@1000.300000000' "${dir}/catalog.json"
  [[ "$(wallpaper_catalog_print_cached_json_if_current "${dir}/catalog.json" "${dir}/hashmap.tsv")" == cached ]]
)

test_trash_selection() (
  source "${WALLPAPER_DIR}/lib/picker.bash"
  local dir catalog first second chosen="" backend_calls=0 fail_trash=1
  dir="$(mktemp -d)"
  trap 'rm -rf -- "${dir}"' EXIT
  first="${dir}/first wall.jpg"
  second="${dir}/second.jpg"
  catalog="${dir}/catalog.json"
  : >"${first}"; : >"${second}"
  jq -n --arg first "${first}" --arg second "${second}" \
    '[{basename:"first wall.jpg",path:$first,sqre:"/one"},{basename:"second.jpg",path:$second,sqre:"/two"}]' >"${catalog}"

  local active_wallpaper_link="${dir}/wall.set" wallpaper_notifications_disabled=1
  ln -s "${first}" "${active_wallpaper_link}"
  print_log() { :; }
  wallpaper_resolve_path() { readlink -f -- "$1"; }
  wallpaper_catalog_load_file() { chosen="$1"; }
  wallpaper_apply_selected() { ln -sfn "${chosen}" "${active_wallpaper_link}"; }
  wallpaper_apply_backend() { backend_calls=$((backend_calls + 1)); }
  gio() {
    [[ "$1" == trash && "$2" == -- ]] || return 1
    ((fail_trash == 0)) || return 1
    mv -- "$3" "${dir}/trashed.jpg"
  }

  [[ "$(wallpaper_selected_fields "${catalog}" 1)" == $'second.jpg\t'"${second}"$'\t/two' ]]
  refute wallpaper_trash_selected "${catalog}" "${first}"
  [[ -f "${first}" && "$(readlink "${active_wallpaper_link}")" == "${first}" ]]

  fail_trash=0
  wallpaper_trash_selected "${catalog}" "${first}"
  [[ -f "${dir}/trashed.jpg" && ! -e "${first}" ]]
  [[ "$(readlink "${active_wallpaper_link}")" == "${second}" && "${backend_calls}" -eq 1 ]]
  jq -e --arg second "${second}" 'length == 1 and .[0].path == $second' "${catalog}" >/dev/null

  refute wallpaper_trash_selected "${catalog}" "${second}"
  [[ -f "${second}" ]]
)

test_queue() (
  local tmp_dir pending_count temp_count i
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "${tmp_dir}"' EXIT
  printf 'test\n' >"${tmp_dir}/wall.jpg"
  source "${WALLPAPER_DIR}/wallcache.daemon.sh"
  WALLCACHE_QUEUE_ROOT="${tmp_dir}/queue"
  WALLCACHE_PENDING_DIR="${WALLCACHE_QUEUE_ROOT}/pending"
  WALLCACHE_RUNNING_DIR="${WALLCACHE_QUEUE_ROOT}/running"
  WALLPAPER_THUMB_DIR="${tmp_dir}/thumbs"
  wallcache_prepare_queue_directories
  for i in {1..16}; do wallcache_enqueue_wallpaper "${tmp_dir}/wall.jpg" & done
  wait
  pending_count="$(find "${WALLCACHE_PENDING_DIR}" -type f -name '*.job' | wc -l)"
  temp_count="$(find "${WALLCACHE_PENDING_DIR}" -type f -name '.*.job.*' | wc -l)"
  [[ "${pending_count}:${temp_count}" == 1:0 ]]
)

test_index_helpers() (
  source "${WALLPAPER_DIR%/wallpaper}/core/wallpaper.catalog.bash"
  source "${WALLPAPER_DIR}/lib/catalog.bash"
  local -a wallpaper_paths=(/w/a.jpg "/w/b c.png" /w/東京.jpg)

  [[ "$(catalog_index_of wallpaper_paths /w/a.jpg)" == 0 ]]
  [[ "$(catalog_index_of wallpaper_paths "/w/b c.png")" == 1 ]]
  [[ "$(catalog_index_of wallpaper_paths /w/東京.jpg)" == 2 ]]
  refute catalog_index_of wallpaper_paths /w/missing.jpg

  local -a empty=()
  refute catalog_index_of empty /w/a.jpg

  # wraps in both directions, and a single-entry list stays put
  [[ "$(catalog_adjacent_index 0 n 3)" == 1 ]]
  [[ "$(catalog_adjacent_index 2 n 3)" == 0 ]]
  [[ "$(catalog_adjacent_index 0 p 3)" == 2 ]]
  [[ "$(catalog_adjacent_index 2 p 3)" == 1 ]]
  [[ "$(catalog_adjacent_index 0 n 1)" == 0 ]]
  [[ "$(catalog_adjacent_index 0 p 1)" == 0 ]]

  refute catalog_adjacent_index 0 n 0
  refute catalog_adjacent_index 0 x 3
)

test_select_adjacent() (
  source "${WALLPAPER_DIR%/wallpaper}/core/wallpaper.catalog.bash"
  source "${WALLPAPER_DIR}/lib/catalog.bash"
  source "${WALLPAPER_DIR}/lib/apply.bash"
  # stubs must follow the sources, or the libraries redefine them
  print_log() { :; }
  wallpaper_resolve_path() { printf '%s\n' "${current_link_target}"; }
  wallpaper_apply_selected() { applied="${wallpaper_paths[selected_wallpaper_index]}"; }

  local active_wallpaper_link=/unused applied="" selected_wallpaper_index=0 current_link_target=""
  local -a wallpaper_paths=(/w/a.jpg /w/b.jpg /w/c.jpg)

  current_link_target=/w/b.jpg
  wallpaper_select_adjacent n
  [[ "${selected_wallpaper_index}:${applied}" == 2:/w/c.jpg ]]

  current_link_target=/w/c.jpg
  wallpaper_select_adjacent n
  [[ "${selected_wallpaper_index}:${applied}" == 0:/w/a.jpg ]]

  current_link_target=/w/a.jpg
  wallpaper_select_adjacent p
  [[ "${selected_wallpaper_index}:${applied}" == 2:/w/c.jpg ]]

  # unknown current wallpaper falls back to the first entry
  current_link_target=/w/gone.jpg
  wallpaper_select_adjacent n
  [[ "${selected_wallpaper_index}:${applied}" == 0:/w/a.jpg ]]
)

test_parser
test_actions
test_json
test_json_cache_freshness
test_trash_selection
test_queue
test_index_helpers
test_select_adjacent

test_prune_unreferenced() (
  print_log() { :; }
  source "${WALLPAPER_DIR}/lib/cache-prune.bash"
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf -- "${dir}"' EXIT

  : >"${dir}/aabb11.thmb"; : >"${dir}/ccdd22.sqre"
  : >"${dir}/.eeff33.blur"; : >"${dir}/notahash.txt"
  local -A keep=([aabb11]=1)

  wallpaper_prune_unreferenced keep "${dir}" \
    '^\.?([0-9a-fA-F]+)\.(thmb|sqre|blur|quad)(\.png)?$' "stale thumbs"

  [[ -f "${dir}/aabb11.thmb" ]]      # referenced hash survives
  [[ ! -f "${dir}/ccdd22.sqre" ]]    # unreferenced is removed
  [[ ! -f "${dir}/.eeff33.blur" ]]   # leading-dot form is matched too
  [[ -f "${dir}/notahash.txt" ]]     # non-matching names are never touched

  # a missing directory is not an error
  wallpaper_prune_unreferenced keep "${dir}/gone" '^([0-9a-fA-F]+)\.png$' x
)

test_prune_unreferenced

test_selected_path_is_the_only_catalog_read() (
  source "${WALLPAPER_DIR%/wallpaper}/core/wallpaper.catalog.bash"
  source "${WALLPAPER_DIR}/lib/catalog.bash"
  source "${WALLPAPER_DIR}/lib/apply.bash"
  local -a wallpaper_paths=(/w/a.jpg /w/b.jpg /w/c.jpg)
  local selected_wallpaper_index=1
  [[ "$(wallpaper_selected_path)" == /w/b.jpg ]]
  selected_wallpaper_index=2
  [[ "$(wallpaper_selected_path)" == /w/c.jpg ]]
  # an empty catalog yields nothing rather than failing
  local -a empty=(); wallpaper_paths=("${empty[@]}"); selected_wallpaper_index=0
  [[ -z "$(wallpaper_selected_path)" ]]
)

test_ensure_hash_names_the_map_it_writes() (
  source "${WALLPAPER_DIR}/lib/apply.bash"
  wallpaper_file_hash() { printf 'hash-of-%s\n' "${1##*/}"; }
  local -A hashes=()

  wallpaper_ensure_hash hashes /w/a.jpg
  [[ "${hashes[/w/a.jpg]}" == hash-of-a.jpg ]]

  # an existing entry is kept, not recomputed
  hashes[/w/b.jpg]=preset
  wallpaper_ensure_hash hashes /w/b.jpg
  [[ "${hashes[/w/b.jpg]}" == preset ]]

  # it writes to whichever map the caller names
  local -A other=()
  wallpaper_ensure_hash other /w/c.jpg
  [[ "${other[/w/c.jpg]}" == hash-of-c.jpg && -z "${hashes[/w/c.jpg]:-}" ]]

  refute wallpaper_ensure_hash hashes ""
)

test_link_selected_uses_the_path_it_is_given() (
  source "${WALLPAPER_DIR}/lib/apply.bash"
  wallpaper_prepare_notification_payload() { payload_arg="$1"; }
  local dir payload_arg=""
  dir="$(mktemp -d)"; trap 'rm -rf -- "${dir}"' EXIT
  local active_wallpaper_link="${dir}/wall.set" current_wallpaper_link="${dir}/current"
  : >"${dir}/chosen.png"

  # deliberately disagrees with the catalog: the argument must win
  local -a wallpaper_paths=(/w/ignored.jpg); local selected_wallpaper_index=0
  wallpaper_link_selected "${dir}/chosen.png"

  [[ "$(readlink "${active_wallpaper_link}")" == "${dir}/chosen.png" ]]
  [[ "$(readlink "${current_wallpaper_link}")" == "${dir}/chosen.png" ]]
  current_wallpaper_link=""
  wallpaper_link_selected "${dir}/chosen.png"
  [[ "$(readlink "${active_wallpaper_link}")" == "${dir}/chosen.png" ]]
  [[ "${payload_arg}" == "${dir}/chosen.png" ]]
)

test_theme_catalog_repairs_wall_link() (
  source "${WALLPAPER_DIR%/wallpaper}/core/wallpaper.catalog.bash"
  local temp_dir wall
  local -a theme_names=() theme_wallpapers=() WALLPAPER_FILETYPES=() WALLPAPER_OVERRIDE_FILETYPES=()
  temp_dir="$(mktemp -d)"; trap 'rm -rf -- "${temp_dir}"' EXIT
  HYPR_CONFIG_HOME="${temp_dir}/config" HYPR_HASH_COMMAND=sha1sum
  wall="${HYPR_CONFIG_HOME}/themes/Pack/wallpapers/wall.jpg"
  mkdir -p "${wall%/*}"
  printf 'image\n' >"${wall}"
  theme_catalog_load_and_repair_links_into theme_names theme_wallpapers
  [[ "${theme_names[*]}" == Pack && "${theme_wallpapers[0]}" == "${wall}" ]]
  [[ "$(readlink "${HYPR_CONFIG_HOME}/themes/Pack/wall.set")" == "${wall}" ]]
)

test_selected_path_is_the_only_catalog_read
test_ensure_hash_names_the_map_it_writes
test_link_selected_uses_the_path_it_is_given
test_theme_catalog_repairs_wall_link

test_notification_follows_replacement_path() (
  source "${WALLPAPER_DIR}/lib/apply.bash"
  source "${WALLPAPER_DIR}/lib/notifications.bash"
  local -A wallpaper_hash_by_path=([/w/first.jpg]=aaa [/w/replacement.jpg]=bbb)
  local WALLPAPER_THUMB_DIR=/thumbs selected_wallpaper_path=/w/first.jpg
  local selected_wallpaper=first.jpg selected_thumbnail=/thumbs/aaa.sqre
  wallpaper_prepare_notification_payload /w/replacement.jpg
  [[ "${selected_wallpaper_path}" == /w/replacement.jpg ]]
  [[ "${HYPR_WALLPAPER_NOTIFY_NAME}" == replacement.jpg ]]
  [[ "${HYPR_WALLPAPER_NOTIFY_ICON}" == /thumbs/bbb.sqre ]]
)

test_cache_worker_reports_failure() (
  source "${WALLPAPER_DIR}/cache/render.bash"
  local directory extension
  directory="$(mktemp -d)"; trap 'rm -rf -- "${directory}"' EXIT
  local WALLPAPER_THUMB_DIR="${directory}" TMPDIR="${directory}" NOTIFY_BRIEF_MS=0
  hypr_magick_limit_args_into() { :; }
  wallpaper_is_video() { return 1; }
  magick() { return 1; }
  refute wallcache_render_wallpaper hash "${directory}/source.jpg" 0
  refute wallcache_render_wallpaper hash "${directory}/source.jpg" 1
  refute wallcache_write_masked_thumbnail hash
  for extension in thmb sqre blur quad; do : >"${directory}/hash.${extension}"; done
  wallcache_render_wallpaper hash "${directory}/source.jpg" 0
  wallpaper_is_video() { return 0; }
  send_ephemeral_notif() { :; }
  extract_thumbnail() { : >"$2"; return 1; }
  refute wallcache_render_wallpaper video "${directory}/source.mp4" 0
  [[ ! -e "${directory}/video.png" ]]
)

test_cache_job_budget_cannot_divide_by_zero() (
  source "${WALLPAPER_DIR}/cache/batch.bash"
  local WALLPAPER_CACHE_JOB_MB=0 WALLPAPER_CACHE_JOBS="" WALLPAPER_CACHE_RESERVE_MB=0
  [[ "$(wallcache_job_count 4 4800)" == 4 ]]
)

test_notification_follows_replacement_path
test_cache_worker_reports_failure
test_cache_job_budget_cannot_divide_by_zero
