github_response_header_value() {
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

github_response_message() {
  local body_file="$1"
  local fallback="$2"
  local message

  message="$(jq -r '.message // empty' "$body_file" 2>/dev/null)"
  if [ -z "$message" ]; then
    message="$fallback"
  fi
  printf '%s' "$message"
}

github_response_context() {
  local headers_file="$1"
  local accepted_perms token_scopes accepted_scopes rate_remaining context

  accepted_perms="$(github_response_header_value "x-accepted-github-permissions" "$headers_file")"
  token_scopes="$(github_response_header_value "x-oauth-scopes" "$headers_file")"
  accepted_scopes="$(github_response_header_value "x-accepted-oauth-scopes" "$headers_file")"
  rate_remaining="$(github_response_header_value "x-ratelimit-remaining" "$headers_file")"

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

  printf '%s' "${context#$'\n'}"
}

github_api_request_status() {
  local token="$1"
  shift
  # a bar provider must return: without these a stalled connection hangs the
  # module forever, and the button renders as empty text. A failed transfer
  # still prints 000 for the caller; its exit status would abort under set -e.
  curl -sS \
    --connect-timeout "${GITHUB_CONNECT_TIMEOUT}" \
    --max-time "${GITHUB_MAX_TIME}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" \
    -w '%{http_code}' \
    "$@" || true
}

github_get_http_status() {
  local token="$1" url="$2" body_file="$3" headers_file="$4"
  github_api_request_status "$token" -L -D "$headers_file" -o "$body_file" "$url"
}

github_next_page_url() {
  sed -n 's/^[Ll]ink:.*<\([^>]*\)>; rel="next".*/\1/p' "$1" | tr -d '\r' | tail -n 1
}
