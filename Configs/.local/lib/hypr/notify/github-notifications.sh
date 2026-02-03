#!/usr/bin/env bash

# Load pywal colors
[ -f "$HOME/.cache/wal/colors.sh" ] && source "$HOME/.cache/wal/colors.sh"

check() {
  command -v "$1" &>/dev/null
}

notify() {
  check notify-send && notify-send "$@" || echo "$@"
}

TOKEN_FILE="$HOME/.config/github/notifications.token"
USER_FILE="$HOME/.config/github/username"
REPOS_CACHE="$HOME/.cache/github/repos.list"

# Ensure token exists
if [ ! -f "$TOKEN_FILE" ]; then
  notify "Ensure you have placed your GitHub token in $TOKEN_FILE"
  cat <<EOF
{"text":"NaN","tooltip":"Token not found"}
EOF
  exit 1
fi

# Try to read GitHub username (optional)
if [ -f "$USER_FILE" ]; then
  GH_USER=$(cat "$USER_FILE")
else
  # Try to infer username using token
  TOKEN=$(cat "$TOKEN_FILE")
  GH_USER=$(curl -s -u ":$TOKEN" https://api.github.com/user | jq -r '.login')

  if [ -z "$GH_USER" ] || [ "$GH_USER" = "null" ]; then
    notify "Could not determine GitHub username. Create $USER_FILE manually."
    GH_USER="unknown"
  else
    mkdir -p "$(dirname "$USER_FILE")"
    echo "$GH_USER" >"$USER_FILE"
  fi
fi

TOKEN=$(cat "$TOKEN_FILE")

# Fetch regular notifications count
notif_count=$(curl -su "$GH_USER:$TOKEN" https://api.github.com/notifications | jq '. | length' 2>/dev/null)
if [ -z "$notif_count" ] || ! [[ "$notif_count" =~ ^[0-9]+$ ]]; then
  notif_count="0"
fi

# Fetch security alerts count (Dependabot)
# Cache repo list for 1 day to reduce API calls
mkdir -p "$(dirname "$REPOS_CACHE")"
if [ ! -f "$REPOS_CACHE" ] || [ "$(find "$REPOS_CACHE" -mmin +1440 2>/dev/null)" ]; then
  curl -s -u "$GH_USER:$TOKEN" "https://api.github.com/user/repos?per_page=100&affiliation=owner" | jq -r '.[].full_name' >"$REPOS_CACHE" 2>/dev/null
fi

security_count=0
security_details=""
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  count=$(curl -s -u "$GH_USER:$TOKEN" "https://api.github.com/repos/$repo/dependabot/alerts?state=open&per_page=100" 2>/dev/null | jq 'if type == "array" then length else 0 end')
  if [ -n "$count" ] && [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ]; then
    security_count=$((security_count + count))
    repo_name="${repo#*/}"
    security_details+="  $repo_name: $count\n"
  fi
done <"$REPOS_CACHE"

# Build tooltip
tooltip="<b>GitHub Notifications</b>\n"
tooltip+=" Inbox: $notif_count\n"
tooltip+=" Security: $security_count"
if [ -n "$security_details" ]; then
  tooltip+="\n$security_details"
fi

# Build display text
if [ "$notif_count" -gt 0 ] && [ "$security_count" -gt 0 ]; then
  text="<span color='${color11:-#E6C384}'></span>"
elif [ "$notif_count" -gt 0 ]; then
  text="<span color='${color10:-#98BB6C}'></span>"
elif [ "$security_count" -gt 0 ]; then
  text="<span color='${color9:-#E82424}'></span>"
else
  text="<span color='${foreground:-}'></span>"
fi

# Output JSON for Waybar
cat <<EOF
{"text":"$text","tooltip":"$tooltip"}
EOF
