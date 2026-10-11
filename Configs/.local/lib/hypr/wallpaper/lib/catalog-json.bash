#!/usr/bin/env bash

wallpaper_catalog_prepare_runtime() {
  local ensure_thumbs="${1:-0}"
  selected_wallpaper_index=0
  if ! wallpaper_theme_sources; then
    echo "ERROR: \"${HYPR_THEME_DIR}\" does not exist"
    return 2
  fi

  wallpaper_hashmap_cached "${wallpaper_source_paths[@]}" || return 1
  [[ "${ensure_thumbs}" -eq 1 ]] && wallpaper_enqueue_missing_thumbnails "sqre"
  return 0
}

wallpaper_catalog_cache_paths() {
  local out_cache_home_name="$1"
  local out_cache_file_name="$2"
  local out_json_cache_name="$3"
  local resolved_cache_home=""
  local resolved_cache_file=""
  local resolved_json_cache=""

  resolved_cache_home="$(wallpaper_cache_root)"
  resolved_cache_file="$(wallpaper_hashmap_cache_file "${wallpaper_source_paths[@]}" 2>/dev/null || true)"
  resolved_json_cache="$(wallpaper_catalog_json_file "${wallpaper_source_paths[@]}" 2>/dev/null || true)"

  printf -v "${out_cache_home_name}" '%s' "${resolved_cache_home}"
  printf -v "${out_cache_file_name}" '%s' "${resolved_cache_file}"
  printf -v "${out_json_cache_name}" '%s' "${resolved_json_cache}"
}

wallpaper_catalog_print_cached_json_if_current() {
  local json_cache="$1"
  local cache_file="$2"

  [[ -n "${json_cache}" && -f "${json_cache}" && -f "${cache_file}" ]] || return 1
  [[ "${json_cache}" -nt "${cache_file}" ]] || return 1
  cat "${json_cache}"
}

wallpaper_catalog_build_json() {
  local cache_home="$1"
  local path=""
  for path in "${wallpaper_paths[@]}"; do printf '%s\0%s\0' "${path}" "${wallpaper_hash_by_path["${path}"]}"; done |
    jq -Rs --arg cacheHome "${cache_home}" '
        split("\u0000") as $catalog | [range(0; $catalog | length - 1; 2) as $i |
            {
                path: $catalog[$i], hash: $catalog[$i + 1],
                basename: ($catalog[$i] | split("/") | last),
                thmb: "\($cacheHome)/thumbs/\($catalog[$i + 1]).thmb",
                sqre: "\($cacheHome)/thumbs/\($catalog[$i + 1]).sqre",
                blur: "\($cacheHome)/thumbs/\($catalog[$i + 1]).blur",
                quad: "\($cacheHome)/thumbs/\($catalog[$i + 1]).quad",
                rofi_sqre: "\($catalog[$i] | split("/") | last):::\($catalog[$i]):::\($cacheHome)/thumbs/\($catalog[$i + 1]).sqre\u0000icon\u001f\($cacheHome)/thumbs/\($catalog[$i + 1]).sqre",
                rofi_thmb: "\($catalog[$i] | split("/") | last):::\($catalog[$i]):::\($cacheHome)/thumbs/\($catalog[$i + 1]).thmb\u0000icon\u001f\($cacheHome)/thumbs/\($catalog[$i + 1]).thmb",
                rofi_blur: "\($catalog[$i] | split("/") | last):::\($catalog[$i]):::\($cacheHome)/thumbs/\($catalog[$i + 1]).blur\u0000icon\u001f\($cacheHome)/thumbs/\($catalog[$i + 1]).blur",
                rofi_quad: "\($catalog[$i] | split("/") | last):::\($catalog[$i]):::\($cacheHome)/thumbs/\($catalog[$i + 1]).quad\u0000icon\u001f\($cacheHome)/thumbs/\($catalog[$i + 1]).quad"
            }
        ]
    '
}

wallpaper_catalog_emit_and_cache_json() {
  local cache_home="$1"
  local json_cache="$2"
  [[ -n "${json_cache}" ]] || { wallpaper_catalog_build_json "${cache_home}"; return; }

  local json_tmp="${json_cache}.tmp"
  mkdir -p "${json_cache%/*}"
  wallpaper_catalog_build_json "${cache_home}" >"${json_tmp}" || { rm -f "${json_tmp}"; return 1; }
  mv -f "${json_tmp}" "${json_cache}"
  cat "${json_cache}"
}

wallpaper_json() (
  local ensure_thumbs=0
  local cache_home=""
  local cache_file=""
  local json_cache=""
  local prepare_status=0

  if [[ "${1:-}" == "--ensure-thumbs" ]]; then
    ensure_thumbs=1
    shift
  fi

  wallpaper_catalog_lock || exit 1
  wallpaper_catalog_prepare_runtime "${ensure_thumbs}" || prepare_status=$?
  if ((prepare_status != 0)); then
    [[ "${prepare_status}" -eq 2 ]] && exit 0
    exit "${prepare_status}"
  fi
  wallpaper_catalog_cache_paths cache_home cache_file json_cache

  wallpaper_catalog_print_cached_json_if_current "${json_cache}" "${cache_file}" && return 0
  wallpaper_catalog_emit_and_cache_json "${cache_home}" "${json_cache}"
)
