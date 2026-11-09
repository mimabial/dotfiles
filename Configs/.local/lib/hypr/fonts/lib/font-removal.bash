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

partition_unused_local_families_into() {
  local -n removable_families_ref="$1" kept_families_ref="$2" removable_counts_ref="$3" provider_counts_ref="$4" removable_files_ref="$5"
  local -A listed_files=()
  local family file_path file_count safe_file_count
  for family in "${LOCAL_UNUSED_FAMILIES[@]}"; do
    file_count=0
    safe_file_count=0
    while IFS= read -r file_path; do
      [[ -n "${file_path}" ]] || continue
      file_count=$((file_count + 1))
      file_is_removable "${file_path}" || continue
      safe_file_count=$((safe_file_count + 1))
      [[ -n "${listed_files[$file_path]:-}" ]] && continue
      listed_files["${file_path}"]=1
      removable_files_ref+=("${file_path}")
    done < <(family_files "${family}")

    removable_counts_ref["${family}"]="${safe_file_count}"
    provider_counts_ref["${family}"]="${file_count}"
    if ((safe_file_count > 0)); then
      removable_families_ref+=("${family}")
    else
      kept_families_ref+=("${family}")
    fi
  done
}
