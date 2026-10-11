# A file is only safe to delete when every family it provides is itself
# unreferenced -- one live alias keeps the whole file. This is the sole
# criterion for both the count that is reported and the files that are removed.
file_is_removable() {
  local file_family
  while IFS= read -r file_family; do
    [[ -n "${file_family}" ]] || continue
    [[ -n "${UNUSED_LOCAL_FAMILY_MAP[$file_family]:-}" ]] || return 1
  done <<<"${LOCAL_FILE_FAMILIES[$1]}"
}

partition_unused_local_families() {
  LOCAL_REMOVABLE_FAMILIES=()
  LOCAL_KEPT_PROVIDER_FAMILIES=()
  LOCAL_REMOVABLE_FILE_COUNTS=()
  LOCAL_PROVIDER_FILE_COUNTS=()

  local family file_path file_count safe_file_count
  for family in "${LOCAL_UNUSED_FAMILIES[@]}"; do
    file_count=0
    safe_file_count=0
    while IFS= read -r file_path; do
      [[ -n "${file_path}" ]] || continue
      file_count=$((file_count + 1))
      file_is_removable "${file_path}" && safe_file_count=$((safe_file_count + 1))
    done < <(family_files "${family}")

    LOCAL_REMOVABLE_FILE_COUNTS["${family}"]="${safe_file_count}"
    LOCAL_PROVIDER_FILE_COUNTS["${family}"]="${file_count}"
    if ((safe_file_count > 0)); then
      LOCAL_REMOVABLE_FAMILIES+=("${family}")
    else
      LOCAL_KEPT_PROVIDER_FAMILIES+=("${family}")
    fi
  done
}

collect_removable_local_files() {
  REMOVABLE_LOCAL_FILES=()
  local -A seen=()
  local family file_path
  for family in "${LOCAL_REMOVABLE_FAMILIES[@]}"; do
    while IFS= read -r file_path; do
      [[ -n "${file_path}" ]] || continue
      [[ -n "${seen[$file_path]:-}" ]] && continue
      file_is_removable "${file_path}" || continue
      seen["${file_path}"]=1
      REMOVABLE_LOCAL_FILES+=("${file_path}")
    done < <(family_files "${family}")
  done
}
