emit_github_bar_status_json() {
  if [ -n "${2:-}" ]; then
    printf '{"text":"%s","class":"%s"}\n' "$1" "$2"
  else
    printf '{"text":"%s"}\n' "$1"
  fi
}

emit_github_failure() {
  local mode="$1" message="$2"
  local json_message="${message//\\/\\\\}"
  json_message="${json_message//\"/\\\"}"

  printf 'GitHub Notifications: %s\n' "${message}" >&2
  case "${mode}" in
    status) emit_github_bar_status_json "" "error" ;;
    report) printf '{"inbox":{"available":false,"issue":"%s"},"security":{"available":false}}\n' "${json_message}" ;;
    mark) return 1 ;;
  esac
}

emit_github_notifications_report() {
  jq -n \
    --arg notif_available "${notif_available:-0}" \
    --arg notif_count "${notif_count:-0}" \
    --arg notif_issue "${notif_issue:-}" \
    --argjson notif_items "${notif_items:-[]}" \
    --argjson review_items "${review_items:-[]}" \
    --arg review_issue "${review_issue:-}" \
    --arg security_available "${security_available:-0}" \
    --arg security_count "${security_count:-0}" \
    --arg dependabot_count "${dependabot_count:-0}" \
    --arg code_scanning_count "${code_scanning_count:-0}" \
    --arg secret_scanning_count "${secret_scanning_count:-0}" \
    --arg dependabot_details "${dependabot_details:-}" \
    --arg code_scanning_details "${code_scanning_details:-}" \
    --arg secret_scanning_details "${secret_scanning_details:-}" \
    --arg security_issue "${security_issue:-}" \
    --arg security_note "${security_note:-}" \
    '
    def num: try tonumber catch 0;
    def repos: split("\n")
      | map(select(test("\\S")) | sub("^\\s+"; "") | split(": "))
      | map(select(length == 2))
      | map({repo: .[0], count: (.[1] | num)});
    {
      inbox: {
        available: ($notif_available == "1"),
        count: ($notif_count | num),
        issue: $notif_issue,
        items: $notif_items
      },
      reviews: {
        items: $review_items,
        issue: $review_issue
      },
      security: {
        available: ($security_available == "1"),
        count: ($security_count | num),
        issue: $security_issue,
        note: $security_note,
        kinds: [
          {key: "dependabot", label: "Dependabot",
           count: ($dependabot_count | num), repos: ($dependabot_details | repos)},
          {key: "code-scanning", label: "Code scanning",
           count: ($code_scanning_count | num), repos: ($code_scanning_details | repos)},
          {key: "secret-scanning", label: "Secret scanning",
           count: ($secret_scanning_count | num), repos: ($secret_scanning_details | repos)}
        ]
      }
    }'
}

emit_github_notifications_status() {
  if [ "$notif_available" -eq 0 ] && [ "$security_available" -eq 0 ]; then
    emit_github_bar_status_json "" "error"
    return 0
  fi

  if [ "$notif_available" -eq 0 ] || [ "$security_available" -eq 0 ] || [ -n "$notif_issue" ] || [ -n "$security_note" ] || [ -n "$security_issue" ]; then
    emit_github_bar_status_json "" "degraded"
    return 0
  fi

  if [ "$notif_count" -gt 0 ] && [ "$security_count" -gt 0 ]; then
    emit_github_bar_status_json "" "inbox-security"
  elif [ "$notif_count" -gt 0 ]; then
    emit_github_bar_status_json "" "inbox"
  elif [ "$security_count" -gt 0 ]; then
    emit_github_bar_status_json "" "security"
  else
    emit_github_bar_status_json ""
  fi
}
