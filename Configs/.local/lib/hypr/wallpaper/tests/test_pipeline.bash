#!/usr/bin/env bash
set -euo pipefail

WALLPAPER_DIR="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)"

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
  wallList=("/tmp/a b.jpg" "/tmp/東京.png")
  declare -A wallHashByPath=(["${wallList[0]}"]=abc ["${wallList[1]}"]=def)
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

test_parser
test_actions
test_json
test_queue
