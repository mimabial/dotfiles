is_nonfatal_alert_unavailable() {
  case "${1,,}" in
    *"disabled for this repository"* | *"not enabled for this repository"* | *"must be enabled for this repository"* | *"secret scanning is disabled"* | *"advanced security must be enabled"* | *"dependabot alerts are disabled"*)
      return 0
      ;;
  esac
  return 1
}

security_cache_is_fresh() {
  local ttl_minutes="${GITHUB_SECURITY_CACHE_TTL_MINUTES:-${GITHUB_SECURITY_CACHE_DEFAULT_TTL_MINUTES}}"
  local ttl_seconds=""
  local mtime

  [[ "$ttl_minutes" =~ ^[0-9]+$ ]] || ttl_minutes="${GITHUB_SECURITY_CACHE_DEFAULT_TTL_MINUTES}"
  ttl_seconds=$((ttl_minutes * 60))
  [ "$ttl_seconds" -gt 0 ] || return 1
  [ -s "$GITHUB_SECURITY_SUMMARY_CACHE" ] || return 1

  mtime="$(stat -c %Y "$GITHUB_SECURITY_SUMMARY_CACHE" 2>/dev/null || echo 0)"
  [[ "$mtime" =~ ^[0-9]+$ ]] || return 1

  [ $((EPOCHSECONDS - mtime)) -le "$ttl_seconds" ] || return 1

  if [ -e "$GITHUB_REPOSITORIES_CACHE" ] && [ "$GITHUB_REPOSITORIES_CACHE" -nt "$GITHUB_SECURITY_SUMMARY_CACHE" ]; then
    return 1
  fi

  return 0
}

load_security_cache() {
  local index
  local -a fields=("${GITHUB_SECURITY_COUNT_FIELDS[@]}" "${GITHUB_SECURITY_TEXT_FIELDS[@]}") values=()
  [ -s "$GITHUB_SECURITY_SUMMARY_CACHE" ] || return 1

  mapfile -d '' -t values < <(jq --raw-output0 '. as $cache | $ARGS.positional[] | $cache[.] // ""' \
    --args "${fields[@]}" <"$GITHUB_SECURITY_SUMMARY_CACHE" 2>/dev/null)
  [ "${#values[@]}" -eq "${#fields[@]}" ] || return 1
  for index in "${!GITHUB_SECURITY_COUNT_FIELDS[@]}"; do
    [[ "${values[index]}" =~ ^[0-9]+$ ]] || return 1
  done
  for index in "${!fields[@]}"; do
    printf -v "${fields[index]}" '%s' "${values[index]}"
  done
}

save_security_cache() {
  local field tmp_cache
  local -a jq_args=(--argjson created_at "${EPOCHSECONDS}")

  for field in "${GITHUB_SECURITY_COUNT_FIELDS[@]}"; do
    jq_args+=(--argjson "$field" "${!field}")
  done
  for field in "${GITHUB_SECURITY_TEXT_FIELDS[@]}"; do
    jq_args+=(--arg "$field" "${!field}")
  done
  mkdir -p "${GITHUB_SECURITY_SUMMARY_CACHE%/*}"
  tmp_cache="$(mktemp)"
  jq -n "${jq_args[@]}" '$ARGS.named' >"$tmp_cache" || {
    rm -f "$tmp_cache"
    return 1
  }
  mv -f "$tmp_cache" "$GITHUB_SECURITY_SUMMARY_CACHE"
}

refresh_repo_cache() {
  local tmp_repos page body_file headers_file code count
  local msg context
  local max_pages=20

  REPO_REFRESH_ERROR=""
  tmp_repos="$(mktemp)"
  : >"$tmp_repos"

  for ((page = 1; page <= max_pages; page++)); do
    body_file="$(mktemp)"
    headers_file="$(mktemp)"
    code="$(github_get_http_status "$GITHUB_ALERTS_TOKEN" "$GITHUB_API/user/repos?per_page=${GITHUB_PAGE_SIZE}&page=${page}&affiliation=owner,collaborator,organization_member" "$body_file" "$headers_file")"

    if [ "$code" -ne 200 ]; then
      msg="$(github_response_message "$body_file" "Failed to fetch repository list")"
      context="$(github_response_context "$headers_file")"
      REPO_REFRESH_ERROR="${msg} (HTTP ${code})"
      if [ -n "$context" ]; then
        REPO_REFRESH_ERROR+=$'\n'"${context}"
      fi
      rm -f "$body_file" "$headers_file" "$tmp_repos"
      return 1
    fi

    count="$(jq -r 'if type == "array" then length else -1 end' "$body_file" 2>/dev/null)"
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
      REPO_REFRESH_ERROR="Unexpected response type"
      rm -f "$body_file" "$headers_file" "$tmp_repos"
      return 1
    fi

    jq -r '.[]?.full_name // empty' "$body_file" >>"$tmp_repos" 2>/dev/null
    rm -f "$body_file" "$headers_file"

    if [ "$count" -lt "$GITHUB_PAGE_SIZE" ]; then
      break
    fi
  done

  mkdir -p "${GITHUB_REPOSITORIES_CACHE%/*}"
  sort -u "$tmp_repos" | sed '/^$/d' >"$GITHUB_REPOSITORIES_CACHE"
  rm -f "$tmp_repos"
  return 0
}

github_note_repo_alert_error() {
  local failures_var="$1"
  local first_error_var="$2"
  local label="$3"
  local repo="$4"
  local body_file="$5"
  local headers_file="$6"
  local http_code="$7"
  local fallback="$8"
  local message context

  printf -v "${failures_var}" '%s' "$(( ${!failures_var} + 1 ))"
  if [ -n "${!first_error_var}" ]; then
    return 0
  fi

  message="$(github_response_message "$body_file" "$fallback")"
  context="$(github_response_context "$headers_file")"
  printf -v "${first_error_var}" '%s' "${label} endpoint (${repo}): ${message} (HTTP ${http_code})"
  if [ -n "$context" ]; then
    printf -v "${first_error_var}" '%s' "${!first_error_var}"$'\n'"${context}"
  fi
}

collect_repo_alert_type() {
  local repo="$1"
  local repo_name="$2"
  local endpoint="$3"
  local label="$4"
  local count_var="$5"
  local details_var="$6"
  local failures_var="$7"
  local first_error_var="$8"
  local fallback="$9"
  local body_file headers_file http_code page_count message
  local url="$GITHUB_API/repos/$repo/$endpoint?state=open&per_page=${GITHUB_PAGE_SIZE}"
  local alert_count=0

  body_file="$(mktemp)"
  headers_file="$(mktemp)"
  while [ -n "$url" ]; do
    http_code="$(github_get_http_status "$GITHUB_ALERTS_TOKEN" "$url" "$body_file" "$headers_file")"
    [ "$http_code" = 200 ] || break
    page_count="$(jq 'if type == "array" then length else 0 end' "$body_file" 2>/dev/null)" || page_count=0
    alert_count=$((alert_count + page_count))
    url="$(github_next_page_url "$headers_file")"
  done

  if [ "$alert_count" -gt 0 ]; then
    printf -v "${count_var}" '%s' "$(( ${!count_var} + alert_count ))"
    printf -v "${details_var}" '%s' "${!details_var}"$'\n'"    ${repo_name}: ${alert_count}"
  fi

  case "$http_code" in
    200 | 404 | 410) ;;
    403)
      message="$(github_response_message "$body_file" "Forbidden")"
      if ! is_nonfatal_alert_unavailable "$message"; then
        github_note_repo_alert_error "$failures_var" "$first_error_var" "$label" "$repo" "$body_file" "$headers_file" "$http_code" "$fallback"
      fi
      ;;
    *)
      github_note_repo_alert_error "$failures_var" "$first_error_var" "$label" "$repo" "$body_file" "$headers_file" "$http_code" "$fallback"
      ;;
  esac

  rm -f "$body_file" "$headers_file"
}

collect_github_security_repo_alerts() {
  local repo repo_name

  dep_failed_requests=0
  code_failed_requests=0
  secret_failed_requests=0
  dep_first_error=""
  code_first_error=""
  secret_first_error=""

  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    repo_name="${repo#*/}"
    collect_repo_alert_type "$repo" "$repo_name" "dependabot/alerts" "dependabot" dependabot_count dependabot_details dep_failed_requests dep_first_error "Failed to fetch dependabot alerts"
    collect_repo_alert_type "$repo" "$repo_name" "code-scanning/alerts" "code-scanning" code_scanning_count code_scanning_details code_failed_requests code_first_error "Failed to fetch code-scanning alerts"
    collect_repo_alert_type "$repo" "$repo_name" "secret-scanning/alerts" "secret-scanning" secret_scanning_count secret_scanning_details secret_failed_requests secret_first_error "Failed to fetch secret-scanning alerts"
  done <"$GITHUB_REPOSITORIES_CACHE"
}

security_repo_cache_is_stale() {
  [ ! -s "$GITHUB_REPOSITORIES_CACHE" ] || [ -n "$(find "$GITHUB_REPOSITORIES_CACHE" -mmin "+${GITHUB_REPOSITORIES_CACHE_TTL_MINUTES}" 2>/dev/null)" ]
}

refresh_security_repo_cache_if_needed() {
  security_repo_cache_is_stale || return 0

  if refresh_repo_cache; then
    return 0
  fi

  if [ -s "$GITHUB_REPOSITORIES_CACHE" ]; then
    security_note="Repo refresh failed; using cached list."
    security_note+=$'\n'"${REPO_REFRESH_ERROR}"
  else
    security_available=0
    security_issue="repos endpoint: ${REPO_REFRESH_ERROR}"
  fi
}

load_cached_security_summary_if_fresh() {
  security_cache_is_fresh || return 1
  load_security_cache || return 1

  security_from_cache=1
  if [ -n "$security_issue" ]; then
    security_note="${security_note:+$security_note$'\n'}Using cached security summary."
    security_note+=$'\n'"${security_issue}"
    security_issue=""
  fi
}

collect_live_security_summary() {
  if [ "$security_available" -eq 1 ] && [ -s "$GITHUB_REPOSITORIES_CACHE" ]; then
    collect_github_security_repo_alerts
    return 0
  fi

  if [ "$security_available" -eq 1 ]; then
    security_available=0
    security_issue="repos endpoint: No accessible repositories found for this token/repo selection."
  fi
}

append_security_failure_notes() {
  if [ "${dep_failed_requests:-0}" -le 0 ] && [ "${code_failed_requests:-0}" -le 0 ] && [ "${secret_failed_requests:-0}" -le 0 ]; then
    return 0
  fi

  security_note="${security_note:+$security_note$'\n'}Some security endpoint requests failed:"
  [ "${dep_failed_requests:-0}" -gt 0 ] && security_note+=$'\n'"  dependabot: ${dep_failed_requests} repo request(s)"
  [ "${code_failed_requests:-0}" -gt 0 ] && security_note+=$'\n'"  code-scanning: ${code_failed_requests} repo request(s)"
  [ "${secret_failed_requests:-0}" -gt 0 ] && security_note+=$'\n'"  secret-scanning: ${secret_failed_requests} repo request(s)"
  [ -n "${dep_first_error:-}" ] && security_note+=$'\n'"${dep_first_error}"
  [ -n "${code_first_error:-}" ] && security_note+=$'\n'"${code_first_error}"
  [ -n "${secret_first_error:-}" ] && security_note+=$'\n'"${secret_first_error}"
  return 0
}

finalize_live_security_summary() {
  security_count=$((dependabot_count + code_scanning_count + secret_scanning_count))
  append_security_failure_notes
  [ "$security_available" -eq 1 ] && save_security_cache >/dev/null 2>&1 || true
}

collect_github_security_state() {
  refresh_security_repo_cache_if_needed
  if load_cached_security_summary_if_fresh; then
    return 0
  fi
  collect_live_security_summary
  [ "$security_from_cache" -eq 1 ] || finalize_live_security_summary
}
