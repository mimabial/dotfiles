#!/usr/bin/env bash

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
NOTIF_TOKEN_FILE="${XDG_CONFIG_HOME}/github/notifications.token"
ALERTS_TOKEN_FILE="${XDG_CONFIG_HOME}/github/alerts.token"
REPOS_CACHE="${XDG_CACHE_HOME}/github/repos.list"
SECURITY_CACHE="${XDG_CACHE_HOME}/github/security-summary.json"
GITHUB_API="https://api.github.com"

check() {
  command -v "$1" >/dev/null 2>&1
}

print_json() {
  local text="$1"
  local tooltip="$2"
  local class_name="$3"

  text="${text//\"/\\\"}"
  tooltip="${tooltip//\"/\\\"}"
  tooltip="${tooltip//$'\n'/\\n}"
  class_name="${class_name//\"/\\\"}"

  if [ -n "$class_name" ]; then
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class_name"
  else
    printf '{"text":"%s","tooltip":"%s"}\n' "$text" "$tooltip"
  fi
}

print_fatal_error() {
  local message="$1"
  local tooltip
  tooltip="<b>GitHub Notifications</b>"
  tooltip+=$'\n'"Error: $message"
  print_json "󰅙" "$tooltip" "error"
  exit 0
}

header_value() {
  local header_name="$1"
  local headers_file="$2"

  awk -F': *' -v wanted="$header_name" '
    {
      key=$1
      val=$2
      gsub(/\r/, "", key)
      gsub(/\r/, "", val)
      if (tolower(key) == tolower(wanted)) {
        print val
        exit
      }
    }
  ' "$headers_file"
}

api_message() {
  local body_file="$1"
  local fallback="$2"
  local message

  message="$(jq -r '.message // empty' "$body_file" 2>/dev/null)"
  if [ -z "$message" ]; then
    message="$fallback"
  fi
  printf '%s' "$message"
}

api_context() {
  local headers_file="$1"
  local accepted_perms token_scopes accepted_scopes rate_remaining context

  accepted_perms="$(header_value "x-accepted-github-permissions" "$headers_file")"
  token_scopes="$(header_value "x-oauth-scopes" "$headers_file")"
  accepted_scopes="$(header_value "x-accepted-oauth-scopes" "$headers_file")"
  rate_remaining="$(header_value "x-ratelimit-remaining" "$headers_file")"

  context=""
  if [ -n "$accepted_perms" ]; then
    context+=$'\n'"Accepted permissions: $accepted_perms"
  fi
  if [ -n "$accepted_scopes" ]; then
    context+=$'\n'"Accepted scopes: $accepted_scopes"
  fi
  if [ -n "$token_scopes" ]; then
    context+=$'\n'"Token scopes: $token_scopes"
  fi
  if [ -n "$rate_remaining" ]; then
    context+=$'\n'"Rate remaining: $rate_remaining"
  fi

  printf '%s' "${context#"$'\n'"}"
}

is_nonfatal_alert_unavailable() {
  local raw_message="$1"
  local message_lc
  message_lc="$(printf '%s' "$raw_message" | tr '[:upper:]' '[:lower:]')"

  case "$message_lc" in
    *"disabled for this repository"* | *"must be enabled for this repository"* | *"secret scanning is disabled"* | *"advanced security must be enabled"* | *"dependabot alerts are disabled"*)
      return 0
      ;;
  esac
  return 1
}

github_get_code() {
  local token="$1"
  local url="$2"
  local body_file="$3"
  local headers_file="$4"

  curl -sS -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -D "$headers_file" \
    -o "$body_file" \
    -w '%{http_code}' \
    "$url"
}

security_cache_is_fresh() {
  local raw="${GITHUB_SECURITY_CACHE_TTL_MINUTES:-240}"
  local ttl_seconds=""
  local now mtime

  [[ "$raw" =~ ^[0-9]+$ ]] || raw=240
  ttl_seconds=$((raw * 60))
  [ "$ttl_seconds" -gt 0 ] || return 1
  [ -s "$SECURITY_CACHE" ] || return 1

  mtime="$(stat -c %Y "$SECURITY_CACHE" 2>/dev/null || echo 0)"
  [[ "$mtime" =~ ^[0-9]+$ ]] || return 1

  now="$(date +%s)"
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  [ $((now - mtime)) -le "$ttl_seconds" ] || return 1

  if [ -e "$REPOS_CACHE" ] && [ "$REPOS_CACHE" -nt "$SECURITY_CACHE" ]; then
    return 1
  fi

  return 0
}

load_security_cache() {
  [ -s "$SECURITY_CACHE" ] || return 1

  security_available="$(jq -r '.security_available // 0' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  security_count="$(jq -r '.security_count // 0' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  dependabot_count="$(jq -r '.dependabot_count // 0' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  code_scanning_count="$(jq -r '.code_scanning_count // 0' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  secret_scanning_count="$(jq -r '.secret_scanning_count // 0' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  dependabot_details="$(jq -r '.dependabot_details // ""' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  code_scanning_details="$(jq -r '.code_scanning_details // ""' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  secret_scanning_details="$(jq -r '.secret_scanning_details // ""' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  security_note="$(jq -r '.security_note // ""' "$SECURITY_CACHE" 2>/dev/null)" || return 1
  security_issue="$(jq -r '.security_issue // ""' "$SECURITY_CACHE" 2>/dev/null)" || return 1

  return 0
}

save_security_cache() {
  local tmp_cache created_at

  mkdir -p "$(dirname "$SECURITY_CACHE")"
  tmp_cache="$(mktemp)"
  created_at="$(date +%s)"

  if ! jq -n \
    --argjson created_at "${created_at}" \
    --argjson security_available "${security_available}" \
    --argjson security_count "${security_count}" \
    --argjson dependabot_count "${dependabot_count}" \
    --argjson code_scanning_count "${code_scanning_count}" \
    --argjson secret_scanning_count "${secret_scanning_count}" \
    --arg dependabot_details "${dependabot_details}" \
    --arg code_scanning_details "${code_scanning_details}" \
    --arg secret_scanning_details "${secret_scanning_details}" \
    --arg security_note "${security_note}" \
    --arg security_issue "${security_issue}" \
    '{
      created_at: $created_at,
      security_available: $security_available,
      security_count: $security_count,
      dependabot_count: $dependabot_count,
      code_scanning_count: $code_scanning_count,
      secret_scanning_count: $secret_scanning_count,
      dependabot_details: $dependabot_details,
      code_scanning_details: $code_scanning_details,
      secret_scanning_details: $secret_scanning_details,
      security_note: $security_note,
      security_issue: $security_issue
    }' >"$tmp_cache"; then
    rm -f "$tmp_cache"
    return 1
  fi

  mv -f "$tmp_cache" "$SECURITY_CACHE"
}

refresh_repo_cache() {
  local tmp_repos page body_file headers_file code count
  local msg context
  local max_pages=20

  REPO_REFRESH_ERROR=""
  tmp_repos="$(mktemp)"
  : >"$tmp_repos"

  for page in $(seq 1 "$max_pages"); do
    body_file="$(mktemp)"
    headers_file="$(mktemp)"
    code="$(github_get_code "$ALERTS_TOKEN" "$GITHUB_API/user/repos?per_page=100&page=${page}&affiliation=owner,collaborator,organization_member" "$body_file" "$headers_file")"

    if [ "$code" -ne 200 ]; then
      msg="$(api_message "$body_file" "Failed to fetch repository list")"
      context="$(api_context "$headers_file")"
      REPO_REFRESH_ERROR="${msg} (HTTP ${code})"
      if [ -n "$context" ]; then
        REPO_REFRESH_ERROR+=$'\n'"${context}"
      fi
      rm -f "$body_file" "$headers_file" "$tmp_repos"
      return 1
    fi

    count="$(jq -r 'if type == "array" then length else -1 end' "$body_file" 2>/dev/null)"
    if [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -lt 0 ]; then
      REPO_REFRESH_ERROR="Unexpected response type"
      rm -f "$body_file" "$headers_file" "$tmp_repos"
      return 1
    fi

    jq -r '.[]?.full_name // empty' "$body_file" >>"$tmp_repos" 2>/dev/null
    rm -f "$body_file" "$headers_file"

    if [ "$count" -lt 100 ]; then
      break
    fi
  done

  mkdir -p "$(dirname "$REPOS_CACHE")"
  sort -u "$tmp_repos" | sed '/^$/d' >"$REPOS_CACHE"
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

  message="$(api_message "$body_file" "$fallback")"
  context="$(api_context "$headers_file")"
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
  local body_file headers_file http_code alert_count message

  body_file="$(mktemp)"
  headers_file="$(mktemp)"
  http_code="$(github_get_code "$ALERTS_TOKEN" "$GITHUB_API/repos/$repo/$endpoint?state=open&per_page=100" "$body_file" "$headers_file")"

  case "$http_code" in
    200)
      alert_count="$(jq -r 'if type == "array" then length else 0 end' "$body_file" 2>/dev/null)"
      if [ -n "$alert_count" ] && [[ "$alert_count" =~ ^[0-9]+$ ]] && [ "$alert_count" -gt 0 ]; then
        printf -v "${count_var}" '%s' "$(( ${!count_var} + alert_count ))"
        printf -v "${details_var}" '%s' "${!details_var}"$'\n'"    ${repo_name}: ${alert_count}"
      fi
      ;;
    404 | 410) ;;
    403)
      message="$(api_message "$body_file" "Forbidden")"
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

ensure_github_notification_deps() {
  if ! check curl || ! check jq; then
    print_fatal_error "Missing curl or jq"
  fi
}

load_github_notification_tokens() {
  NOTIF_TOKEN=""
  ALERTS_TOKEN=""

  if [ -f "$NOTIF_TOKEN_FILE" ]; then
    NOTIF_TOKEN="$(tr -d '\r\n' <"$NOTIF_TOKEN_FILE")"
  fi
  if [ -f "$ALERTS_TOKEN_FILE" ]; then
    ALERTS_TOKEN="$(tr -d '\r\n' <"$ALERTS_TOKEN_FILE")"
  fi

  if [ -z "$NOTIF_TOKEN" ] && [ -z "$ALERTS_TOKEN" ]; then
    print_fatal_error "No token found. Set $NOTIF_TOKEN_FILE and/or $ALERTS_TOKEN_FILE"
  fi
  if [ -z "$NOTIF_TOKEN" ]; then
    NOTIF_TOKEN="$ALERTS_TOKEN"
  fi
  if [ -z "$ALERTS_TOKEN" ]; then
    ALERTS_TOKEN="$NOTIF_TOKEN"
  fi
}

init_github_notification_state() {
  notif_available=1
  notif_count=0
  notif_issue=""

  security_available=1
  security_count=0
  dependabot_count=0
  code_scanning_count=0
  secret_scanning_count=0
  dependabot_details=""
  code_scanning_details=""
  secret_scanning_details=""
  security_note=""
  security_issue=""
  security_from_cache=0
}

collect_github_inbox_state() {
  local notif_body notif_headers notif_code notif_msg notif_context

  notif_body="$(mktemp)"
  notif_headers="$(mktemp)"
  notif_code="$(github_get_code "$NOTIF_TOKEN" "$GITHUB_API/notifications" "$notif_body" "$notif_headers")"
  if [ "$notif_code" -ne 200 ]; then
    notif_available=0
    notif_msg="$(api_message "$notif_body" "Failed to fetch notifications")"
    notif_context="$(api_context "$notif_headers")"
    notif_issue="notifications endpoint: ${notif_msg} (HTTP ${notif_code})"
    if [ "$notif_code" -eq 403 ] && [[ "$notif_msg" == *"personal access token"* ]]; then
      if [ -n "$notif_context" ]; then
        notif_context+=$'\n'
      fi
      notif_context+="Use a classic PAT with notifications scope in $NOTIF_TOKEN_FILE."
    fi
    if [ -n "$notif_context" ]; then
      notif_issue+=$'\n'"${notif_context}"
    fi
  else
    notif_count="$(jq -r 'if type == "array" then length else -1 end' "$notif_body" 2>/dev/null)"
    if [ -z "$notif_count" ] || ! [[ "$notif_count" =~ ^[0-9]+$ ]] || [ "$notif_count" -lt 0 ]; then
      notif_available=0
      notif_count=0
      notif_issue="notifications endpoint: Unexpected response type"
    fi
  fi
  rm -f "$notif_body" "$notif_headers"
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
  done <"$REPOS_CACHE"
}

security_repo_cache_is_stale() {
  [ ! -s "$REPOS_CACHE" ] || [ -n "$(find "$REPOS_CACHE" -mmin +1440 2>/dev/null)" ]
}

refresh_security_repo_cache_if_needed() {
  security_repo_cache_is_stale || return 0

  if refresh_repo_cache; then
    return 0
  fi

  if [ -s "$REPOS_CACHE" ]; then
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
  if [ "$security_available" -eq 1 ] && [ -s "$REPOS_CACHE" ]; then
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

build_github_notifications_tooltip() {
  local tooltip
  tooltip="<b>GitHub Notifications</b>"
  if [ "$notif_available" -eq 1 ]; then
    tooltip+=$'\n'" Inbox: ${notif_count}"
  else
    tooltip+=$'\n'" Inbox: unavailable"
  fi

  if [ "$security_available" -eq 1 ]; then
    tooltip+=$'\n'" Security: ${security_count}"
    tooltip+=$'\n'"  Dependabot: ${dependabot_count}"
    tooltip+=$'\n'"  Code scanning: ${code_scanning_count}"
    tooltip+=$'\n'"  Secret scanning: ${secret_scanning_count}"
    [ -n "$dependabot_details" ] && tooltip+=$'\n'"  Dependabot repos:${dependabot_details}"
    [ -n "$code_scanning_details" ] && tooltip+=$'\n'"  Code scanning repos:${code_scanning_details}"
    [ -n "$secret_scanning_details" ] && tooltip+=$'\n'"  Secret scanning repos:${secret_scanning_details}"
  else
    tooltip+=$'\n'" Security: unavailable"
  fi

  if [ -n "$notif_issue" ] || [ -n "$security_issue" ] || [ -n "$security_note" ]; then
    tooltip+=$'\n'" Issues:"
    [ -n "$notif_issue" ] && tooltip+=$'\n'"  ${notif_issue}"
    [ -n "$security_issue" ] && tooltip+=$'\n'"  ${security_issue}"
    [ -n "$security_note" ] && tooltip+=$'\n'"  ${security_note}"
  fi

  printf '%s' "$tooltip"
}

emit_github_notifications_status() {
  local tooltip
  tooltip="$(build_github_notifications_tooltip)"

  if [ "$notif_available" -eq 0 ] && [ "$security_available" -eq 0 ]; then
    print_json "<span color='${color1:-#E6C384}'>󰅙</span>" "$tooltip" "error"
    return 0
  fi

  if [ "$notif_available" -eq 0 ] || [ "$security_available" -eq 0 ] || [ -n "$notif_issue" ] || [ -n "$security_note" ] || [ -n "$security_issue" ]; then
    print_json "<span color='${color3:-#E6C384}'>󰀪</span>" "$tooltip" "degraded"
    return 0
  fi

  if [ "$notif_count" -gt 0 ] && [ "$security_count" -gt 0 ]; then
    print_json "<span color='${color5:-#E6C384}'></span>" "$tooltip"
  elif [ "$notif_count" -gt 0 ]; then
    print_json "<span color='${color4:-#98BB6C}'></span>" "$tooltip"
  elif [ "$security_count" -gt 0 ]; then
    print_json "<span color='${color1:-#E82424}'></span>" "$tooltip"
  else
    print_json "<span color='${foreground:-#D3C6AA}'></span>" "$tooltip"
  fi
}
