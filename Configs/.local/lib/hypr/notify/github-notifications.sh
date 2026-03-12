#!/usr/bin/env bash

# Load pywal colors (optional, used for normal icon tint).
[ -f "$HOME/.cache/wal/colors.sh" ] && source "$HOME/.cache/wal/colors.sh"

check() {
  command -v "$1" >/dev/null 2>&1
}

NOTIF_TOKEN_FILE="$HOME/.config/github/notifications.token"
ALERTS_TOKEN_FILE="$HOME/.config/github/alerts.token"
REPOS_CACHE="$HOME/.cache/github/repos.list"
GITHUB_API="https://api.github.com"

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

if ! check curl || ! check jq; then
  print_fatal_error "Missing curl or jq"
fi

# Two-token support:
# - notifications.token: /notifications (classic PAT recommended/required by GitHub)
# - alerts.token: security alert endpoints (dependabot/code/secret scanning)
# If one is missing, the other is reused.
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

# Inbox notifications: degrade gracefully when token/endpoint is incompatible.
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

# Repo discovery for security checks, with cache fallback.
cache_is_stale=0
if [ ! -s "$REPOS_CACHE" ] || [ -n "$(find "$REPOS_CACHE" -mmin +1440 2>/dev/null)" ]; then
  cache_is_stale=1
fi

if [ "$cache_is_stale" -eq 1 ]; then
  if ! refresh_repo_cache; then
    if [ -s "$REPOS_CACHE" ]; then
      security_note="Repo refresh failed; using cached list."
      security_note+=$'\n'"${REPO_REFRESH_ERROR}"
    else
      security_available=0
      security_issue="repos endpoint: ${REPO_REFRESH_ERROR}"
    fi
  fi
fi

dep_failed_requests=0
code_failed_requests=0
secret_failed_requests=0
dep_first_error=""
code_first_error=""
secret_first_error=""

if [ "$security_available" -eq 1 ] && [ -s "$REPOS_CACHE" ]; then
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    repo_name="${repo#*/}"

    dep_body="$(mktemp)"
    dep_headers="$(mktemp)"
    dep_code="$(github_get_code "$ALERTS_TOKEN" "$GITHUB_API/repos/$repo/dependabot/alerts?state=open&per_page=100" "$dep_body" "$dep_headers")"

    case "$dep_code" in
      200)
        dep_count="$(jq -r 'if type == "array" then length else 0 end' "$dep_body" 2>/dev/null)"
        if [ -n "$dep_count" ] && [[ "$dep_count" =~ ^[0-9]+$ ]] && [ "$dep_count" -gt 0 ]; then
          dependabot_count=$((dependabot_count + dep_count))
          dependabot_details+=$'\n'"    ${repo_name}: ${dep_count}"
        fi
        ;;
      404 | 410) ;;
      403)
        dep_msg="$(api_message "$dep_body" "Forbidden")"
        if ! is_nonfatal_alert_unavailable "$dep_msg"; then
          dep_failed_requests=$((dep_failed_requests + 1))
          if [ -z "$dep_first_error" ]; then
            dep_context="$(api_context "$dep_headers")"
            dep_first_error="dependabot endpoint (${repo}): ${dep_msg} (HTTP ${dep_code})"
            if [ -n "$dep_context" ]; then
              dep_first_error+=$'\n'"${dep_context}"
            fi
          fi
        fi
        ;;
      *)
        dep_failed_requests=$((dep_failed_requests + 1))
        if [ -z "$dep_first_error" ]; then
          dep_msg="$(api_message "$dep_body" "Failed to fetch dependabot alerts")"
          dep_context="$(api_context "$dep_headers")"
          dep_first_error="dependabot endpoint (${repo}): ${dep_msg} (HTTP ${dep_code})"
          if [ -n "$dep_context" ]; then
            dep_first_error+=$'\n'"${dep_context}"
          fi
        fi
        ;;
    esac
    rm -f "$dep_body" "$dep_headers"

    code_body="$(mktemp)"
    code_headers="$(mktemp)"
    code_http="$(github_get_code "$ALERTS_TOKEN" "$GITHUB_API/repos/$repo/code-scanning/alerts?state=open&per_page=100" "$code_body" "$code_headers")"

    case "$code_http" in
      200)
        code_count="$(jq -r 'if type == "array" then length else 0 end' "$code_body" 2>/dev/null)"
        if [ -n "$code_count" ] && [[ "$code_count" =~ ^[0-9]+$ ]] && [ "$code_count" -gt 0 ]; then
          code_scanning_count=$((code_scanning_count + code_count))
          code_scanning_details+=$'\n'"    ${repo_name}: ${code_count}"
        fi
        ;;
      404 | 410) ;;
      403)
        code_msg="$(api_message "$code_body" "Forbidden")"
        if ! is_nonfatal_alert_unavailable "$code_msg"; then
          code_failed_requests=$((code_failed_requests + 1))
          if [ -z "$code_first_error" ]; then
            code_context="$(api_context "$code_headers")"
            code_first_error="code-scanning endpoint (${repo}): ${code_msg} (HTTP ${code_http})"
            if [ -n "$code_context" ]; then
              code_first_error+=$'\n'"${code_context}"
            fi
          fi
        fi
        ;;
      *)
        code_failed_requests=$((code_failed_requests + 1))
        if [ -z "$code_first_error" ]; then
          code_msg="$(api_message "$code_body" "Failed to fetch code-scanning alerts")"
          code_context="$(api_context "$code_headers")"
          code_first_error="code-scanning endpoint (${repo}): ${code_msg} (HTTP ${code_http})"
          if [ -n "$code_context" ]; then
            code_first_error+=$'\n'"${code_context}"
          fi
        fi
        ;;
    esac
    rm -f "$code_body" "$code_headers"

    secret_body="$(mktemp)"
    secret_headers="$(mktemp)"
    secret_http="$(github_get_code "$ALERTS_TOKEN" "$GITHUB_API/repos/$repo/secret-scanning/alerts?state=open&per_page=100" "$secret_body" "$secret_headers")"

    case "$secret_http" in
      200)
        secret_count="$(jq -r 'if type == "array" then length else 0 end' "$secret_body" 2>/dev/null)"
        if [ -n "$secret_count" ] && [[ "$secret_count" =~ ^[0-9]+$ ]] && [ "$secret_count" -gt 0 ]; then
          secret_scanning_count=$((secret_scanning_count + secret_count))
          secret_scanning_details+=$'\n'"    ${repo_name}: ${secret_count}"
        fi
        ;;
      404 | 410) ;;
      403)
        secret_msg="$(api_message "$secret_body" "Forbidden")"
        if ! is_nonfatal_alert_unavailable "$secret_msg"; then
          secret_failed_requests=$((secret_failed_requests + 1))
          if [ -z "$secret_first_error" ]; then
            secret_context="$(api_context "$secret_headers")"
            secret_first_error="secret-scanning endpoint (${repo}): ${secret_msg} (HTTP ${secret_http})"
            if [ -n "$secret_context" ]; then
              secret_first_error+=$'\n'"${secret_context}"
            fi
          fi
        fi
        ;;
      *)
        secret_failed_requests=$((secret_failed_requests + 1))
        if [ -z "$secret_first_error" ]; then
          secret_msg="$(api_message "$secret_body" "Failed to fetch secret-scanning alerts")"
          secret_context="$(api_context "$secret_headers")"
          secret_first_error="secret-scanning endpoint (${repo}): ${secret_msg} (HTTP ${secret_http})"
          if [ -n "$secret_context" ]; then
            secret_first_error+=$'\n'"${secret_context}"
          fi
        fi
        ;;
    esac
    rm -f "$secret_body" "$secret_headers"
  done <"$REPOS_CACHE"
elif [ "$security_available" -eq 1 ] && [ ! -s "$REPOS_CACHE" ]; then
  security_available=0
  security_issue="repos endpoint: No accessible repositories found for this token/repo selection."
fi

security_count=$((dependabot_count + code_scanning_count + secret_scanning_count))

if [ "$dep_failed_requests" -gt 0 ] || [ "$code_failed_requests" -gt 0 ] || [ "$secret_failed_requests" -gt 0 ]; then
  security_note="${security_note:+$security_note"$'\n'"}Some security endpoint requests failed:"
  [ "$dep_failed_requests" -gt 0 ] && security_note+=$'\n'"  dependabot: ${dep_failed_requests} repo request(s)"
  [ "$code_failed_requests" -gt 0 ] && security_note+=$'\n'"  code-scanning: ${code_failed_requests} repo request(s)"
  [ "$secret_failed_requests" -gt 0 ] && security_note+=$'\n'"  secret-scanning: ${secret_failed_requests} repo request(s)"
  [ -n "$dep_first_error" ] && security_note+=$'\n'"${dep_first_error}"
  [ -n "$code_first_error" ] && security_note+=$'\n'"${code_first_error}"
  [ -n "$secret_first_error" ] && security_note+=$'\n'"${secret_first_error}"
fi

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

# Icon/class policy:
# - error: neither inbox nor security is available
# - degraded: one side unavailable or partial fetch issues
# - normal: both available
if [ "$notif_available" -eq 0 ] && [ "$security_available" -eq 0 ]; then
  print_json "<span color='${color1:-#E6C384}'>󰅙</span>" "$tooltip" "error"
  exit 0
fi

if [ "$notif_available" -eq 0 ] || [ "$security_available" -eq 0 ] || [ -n "$notif_issue" ] || [ -n "$security_note" ] || [ -n "$security_issue" ]; then
  print_json "<span color='${color3:-#E6C384}'>󰀪</span>" "$tooltip" "degraded"
  exit 0
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
