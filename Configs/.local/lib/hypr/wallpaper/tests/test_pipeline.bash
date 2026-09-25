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
  show_help() { exit 90; }
  source "${WALLPAPER_DIR}/lib/parse.bash"
  parse_wallpaper_args_modern --backend hyprpaper -Gn
  [[ "${wallpaper_setter_flag}:${wallpaper_backend}:${set_as_global}" == n:hyprpaper:true ]]
  ! (parse_wallpaper_args_modern next --set /tmp/wall 2>/dev/null)
)

test_actions() (
  print_log() { :; }
  source "${WALLPAPER_DIR}/lib/dispatch.bash"
  local action
  for action in n p r s resume display notify select start link g o clean json; do
    wallpaper_setter_flag="${action}"
    wallpaper_wait_for_lock=0
    wallpaper_resolve_action_profile
    declare -F "${wallpaper_action_handler}" >/dev/null
  done
)

test_json() (
  LIB_DIR="${WALLPAPER_DIR%/hypr/wallpaper}"
  source "${WALLPAPER_DIR}/lib/ui.bash"
  wallpaper_paths=("/tmp/a b.jpg" "/tmp/東京.png")
  declare -A wallpaper_hash_by_path=(["${wallpaper_paths[0]}"]=abc ["${wallpaper_paths[1]}"]=def)
  wallpaper_catalog_build_json /tmp |
    jq -e 'length == 2 and .[0].hash == "abc" and .[1].hash == "def"' >/dev/null
)

test_queue() (
  local tmp_dir pending_count temp_count i
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "${tmp_dir}"' EXIT
  printf 'test\n' >"${tmp_dir}/wall.jpg"
  source "${WALLPAPER_DIR}/wallcache.daemon.sh"
  QUEUE_ROOT="${tmp_dir}/queue"
  QUEUE_PENDING_DIR="${QUEUE_ROOT}/pending"
  QUEUE_RUNNING_DIR="${QUEUE_ROOT}/running"
  WALLPAPER_THUMB_DIR="${tmp_dir}/thumbs"
  ensure_queue_dirs
  for i in {1..16}; do queue_wallpaper "${tmp_dir}/wall.jpg" & done
  wait
  pending_count="$(find "${QUEUE_PENDING_DIR}" -type f -name '*.job' | wc -l)"
  temp_count="$(find "${QUEUE_PENDING_DIR}" -type f -name '.*.job.*' | wc -l)"
  [[ "${pending_count}:${temp_count}" == 1:0 ]]
)

test_index_helpers() (
  source "${WALLPAPER_DIR%/wallpaper}/core/wallpaper.catalog.sh"
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
  source "${WALLPAPER_DIR%/wallpaper}/core/wallpaper.catalog.sh"
  source "${WALLPAPER_DIR}/lib/catalog.bash"
  source "${WALLPAPER_DIR}/lib/actions.bash"
  # stubs must follow the sources, or the libraries redefine them
  print_log() { :; }
  wallpaper_resolve_path() { printf '%s\n' "${current_link_target}"; }
  apply_selected_wallpaper() { applied="${wallpaper_paths[selected_wallpaper_index]}"; }

  local active_wallpaper_link=/unused applied="" selected_wallpaper_index=0 current_link_target=""
  local -a wallpaper_paths=(/w/a.jpg /w/b.jpg /w/c.jpg)

  current_link_target=/w/b.jpg
  select_adjacent_wallpaper n
  [[ "${selected_wallpaper_index}:${applied}" == 2:/w/c.jpg ]]

  current_link_target=/w/c.jpg
  select_adjacent_wallpaper n
  [[ "${selected_wallpaper_index}:${applied}" == 0:/w/a.jpg ]]

  current_link_target=/w/a.jpg
  select_adjacent_wallpaper p
  [[ "${selected_wallpaper_index}:${applied}" == 2:/w/c.jpg ]]

  # unknown current wallpaper falls back to the first entry
  current_link_target=/w/gone.jpg
  select_adjacent_wallpaper n
  [[ "${selected_wallpaper_index}:${applied}" == 0:/w/a.jpg ]]
)

test_parser
test_actions
test_json
test_queue
test_index_helpers
test_select_adjacent

test_prune_unreferenced() (
  print_log() { :; }
  source "${WALLPAPER_DIR}/lib/thumbs.bash"
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
  source "${WALLPAPER_DIR%/wallpaper}/core/wallpaper.catalog.sh"
  source "${WALLPAPER_DIR}/lib/catalog.bash"
  source "${WALLPAPER_DIR}/lib/actions.bash"
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
  source "${WALLPAPER_DIR}/lib/actions.bash"
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
  source "${WALLPAPER_DIR}/lib/actions.bash"
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
  [[ "${payload_arg}" == "${dir}/chosen.png" ]]
)

test_theme_catalog_repairs_wall_link() (
  source "${WALLPAPER_DIR%/wallpaper}/core/wallpaper.catalog.sh"
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
