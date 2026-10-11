ensure_github_notification_deps() {
  command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && return 0
  printf -v "$1" '%s' "Missing curl or jq"
  return 1
}

load_github_notification_tokens() {
  local failure_name="$1"
  GITHUB_NOTIFICATIONS_TOKEN=""
  GITHUB_ALERTS_TOKEN=""

  if [ -f "$GITHUB_NOTIFICATIONS_TOKEN_FILE" ]; then
    GITHUB_NOTIFICATIONS_TOKEN="$(tr -d '\r\n' <"$GITHUB_NOTIFICATIONS_TOKEN_FILE")"
  fi
  if [ -f "$GITHUB_ALERTS_TOKEN_FILE" ]; then
    GITHUB_ALERTS_TOKEN="$(tr -d '\r\n' <"$GITHUB_ALERTS_TOKEN_FILE")"
  fi

  if [ -z "$GITHUB_NOTIFICATIONS_TOKEN" ] && [ -z "$GITHUB_ALERTS_TOKEN" ]; then
    printf -v "${failure_name}" '%s' "No token found. Set $GITHUB_NOTIFICATIONS_TOKEN_FILE and/or $GITHUB_ALERTS_TOKEN_FILE"
    return 1
  fi
  if [ -z "$GITHUB_NOTIFICATIONS_TOKEN" ]; then
    GITHUB_NOTIFICATIONS_TOKEN="$GITHUB_ALERTS_TOKEN"
  fi
  if [ -z "$GITHUB_ALERTS_TOKEN" ]; then
    GITHUB_ALERTS_TOKEN="$GITHUB_NOTIFICATIONS_TOKEN"
  fi
}
