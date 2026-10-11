#!/usr/bin/env bash

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
GITHUB_NOTIFICATIONS_TOKEN_FILE="${XDG_CONFIG_HOME}/github/notifications.token"
GITHUB_ALERTS_TOKEN_FILE="${XDG_CONFIG_HOME}/github/alerts.token"
GITHUB_REPOSITORIES_CACHE="${XDG_CACHE_HOME}/github/repos.list"
GITHUB_SECURITY_SUMMARY_CACHE="${XDG_CACHE_HOME}/github/security-summary.json"
GITHUB_API="https://api.github.com"
GITHUB_API_VERSION="2022-11-28"
GITHUB_PAGE_SIZE=100
GITHUB_REVIEW_REQUEST_LIMIT=50
GITHUB_REPOSITORIES_CACHE_TTL_MINUTES=$((24 * 60))
GITHUB_SECURITY_CACHE_DEFAULT_TTL_MINUTES=$((4 * 60))
GITHUB_CONNECT_TIMEOUT="${GITHUB_CONNECT_TIMEOUT:-5}"
GITHUB_MAX_TIME="${GITHUB_MAX_TIME:-10}"
GITHUB_SECURITY_COUNT_FIELDS=(security_available security_count dependabot_count code_scanning_count secret_scanning_count)
GITHUB_SECURITY_TEXT_FIELDS=(dependabot_details code_scanning_details secret_scanning_details security_note security_issue)

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


source "${BASH_SOURCE[0]%/*}/github-http.bash"
source "${BASH_SOURCE[0]%/*}/github-auth.bash"
source "${BASH_SOURCE[0]%/*}/github-inbox.bash"
source "${BASH_SOURCE[0]%/*}/github-security.bash"
source "${BASH_SOURCE[0]%/*}/github-output.bash"
