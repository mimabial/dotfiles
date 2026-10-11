collect_github_inbox_state() {
  local notif_body notif_headers notif_code notif_msg notif_context

  notif_body="$(mktemp)"
  notif_headers="$(mktemp)"
  notif_code="$(github_get_http_status "$GITHUB_NOTIFICATIONS_TOKEN" "$GITHUB_API/notifications" "$notif_body" "$notif_headers")"
  if [ "$notif_code" -ne 200 ]; then
    notif_available=0
    notif_msg="$(github_response_message "$notif_body" "Failed to fetch notifications")"
    notif_context="$(github_response_context "$notif_headers")"
    notif_issue="notifications endpoint: ${notif_msg} (HTTP ${notif_code})"
    if [ "$notif_code" -eq 403 ] && [[ "$notif_msg" == *"personal access token"* ]]; then
      if [ -n "$notif_context" ]; then
        notif_context+=$'\n'
      fi
      notif_context+="Use a classic PAT with notifications scope in $GITHUB_NOTIFICATIONS_TOKEN_FILE."
    fi
    if [ -n "$notif_context" ]; then
      notif_issue+=$'\n'"${notif_context}"
    fi
  elif ! { read -r notif_count && read -r notif_items; } < <(jq -c '
    select(type == "array") | length, map({
      id, title: .subject.title, type: .subject.type,
      repo: .repository.full_name, reason: (.reason // "" | gsub("_"; " ")),
      url: (.repository.html_url as $home | .subject.url // "" |
        if test("^https://api\\.github\\.com/repos/[^/]+/[^/]+/(pulls|issues|commits|discussions)/[0-9a-f]+$")
        then sub("api\\.github\\.com/repos"; "github.com") | sub("/pulls/"; "/pull/") | sub("/commits/"; "/commit/")
        else $home end)
    })' "$notif_body" 2>/dev/null); then
    notif_available=0
    notif_count=0
    notif_issue="notifications endpoint: Unexpected response type"
  fi
  rm -f "$notif_body" "$notif_headers"
}

collect_github_review_requests() {
  local body headers code

  review_items="[]"
  review_issue=""
  body="$(mktemp)"
  headers="$(mktemp)"
  code="$(github_get_http_status "$GITHUB_NOTIFICATIONS_TOKEN" "$GITHUB_API/search/issues?q=is%3Aopen+is%3Apr+review-requested%3A%40me+draft%3Afalse+archived%3Afalse&per_page=${GITHUB_REVIEW_REQUEST_LIMIT}" "$body" "$headers")"
  if [ "$code" != 200 ] || ! review_items="$(jq -ce '[.items[] | {title, url: .html_url, repo: (.repository_url | sub(".*/repos/"; ""))}]' "$body" 2>/dev/null)"; then
    review_items="[]"
    review_issue="review requests: $(github_response_message "$body" "Failed to search review requests") (HTTP ${code})"
  fi
  rm -f "$body" "$headers"
}

mark_github_notifications_read() {
  local id code failed=0

  for id in "$@"; do
    code="$(github_api_request_status "$GITHUB_NOTIFICATIONS_TOKEN" -X PATCH -o /dev/null "$GITHUB_API/notifications/threads/$id")"
    case "$code" in
      205 | 304) ;;
      *) failed=1 ;;
    esac
  done
  return "$failed"
}
