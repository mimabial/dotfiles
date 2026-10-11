MANAGED_MANIFEST_FILE="${BASH_SOURCE[0]%/*}/../refresh.manifest.psv"

managed_manifest_entry_into() {
  local -n manifest_entry_ref="$1"
  local domain layer kind operation backup_policy relative_path
  IFS='|' read -r domain layer kind operation backup_policy relative_path <<<"$2"
  [[ -n "${domain}" && -n "${layer}" && -n "${kind}" && -n "${operation}" && -n "${backup_policy}" && -n "${relative_path}" ]] || return 1
  manifest_entry_ref=([domain]="${domain}" [layer]="${layer}" [kind]="${kind}" [operation]="${operation}" [backup_policy]="${backup_policy}" [relative_path]="${relative_path}")
}

managed_visit_domains() {
  local visitor_fn="$1" context_name="$2"
  shift 2
  local -a selected_domains=("$@")
  local line selected wanted matched=0
  local -A manifest_entry=()
  [[ -f "${MANAGED_MANIFEST_FILE}" ]] || managed_fail "Missing refresh manifest: ${MANAGED_MANIFEST_FILE}"
  while IFS= read -r line; do
    [[ -n "${line}" && ! "${line}" =~ ^[[:space:]]*# ]] || continue
    managed_manifest_entry_into manifest_entry "${line}" || continue
    if ((${#selected_domains[@]})); then
      wanted=0
      for selected in "${selected_domains[@]}"; do
        [[ "${manifest_entry[domain]}" != "${selected}" ]] || { wanted=1; break; }
      done
      ((wanted)) || continue
    fi
    matched=1
    "${visitor_fn}" manifest_entry "${context_name}"
  done <"${MANAGED_MANIFEST_FILE}"
  ((matched)) || managed_fail "No manifest entries matched: $*"
}

managed_apply_domain_entry() {
  local -n domain_path_ref="$1" domain_run_ref="$2"
  case "${domain_path_ref[kind]}" in
    file | tree) ;;
    *) managed_fail "Unsupported ${domain_run_ref[mode]} kind: ${domain_path_ref[kind]} (${domain_path_ref[relative_path]})" ;;
  esac
  if [[ "${domain_run_ref[mode]}" == restore ]]; then
    domain_path_ref[backup_policy]=always
    [[ "${domain_path_ref[kind]}" == file ]] && domain_path_ref[operation]=overwrite || domain_path_ref[operation]=sync
  fi
  managed_resolve_paths_into "$1"
  managed_apply_path "$1" "$2"
}
