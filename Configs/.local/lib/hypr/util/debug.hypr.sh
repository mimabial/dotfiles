#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell util/debug.hypr
Collect a redacted Hyprland/system debug log and view, save, or upload it." "$@"

LOG_FILE="${TMPDIR:-/tmp}/hypr-debug.log"
redacted_log=""

cleanup_redacted_log() {
  local exit_code="${1:-$?}"
  [[ -n "${redacted_log}" ]] && rm -f "${redacted_log}" 2>/dev/null || true
  return "${exit_code}"
}

redact_debug_log() {
  local src_file="$1"
  local out_file="$2"

  sed -E \
    -e "s|${HOME}|~|g" \
    -e 's/\bgh[pousr]_[A-Za-z0-9_]{20,}\b/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/\bBearer[[:space:]]+[A-Za-z0-9._~-]+\b/Bearer [REDACTED]/g' \
    -e 's/\b([A-Za-z0-9_-]+\.){2}[A-Za-z0-9_-]+\b/[REDACTED_JWT]/g' \
    -e 's/\b([A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|ACCESS_KEY|AUTHORIZATION|COOKIE)[A-Za-z0-9_]*)(=|:[[:space:]]*)[^[:space:]]+/\1\3[REDACTED]/Ig' \
    "${src_file}" >"${out_file}"
}

confirm_upload() {
  cat <<'EOF'
Warning: This uploads a redacted debug log to 0x0.st.
It still contains system, package, journal, and dmesg details.
Review the log first if you are not comfortable sharing machine metadata.
EOF
  printf 'Type UPLOAD to continue: ' >/dev/tty
  local confirm=""
  read -r confirm </dev/tty || return 1
  [[ "${confirm}" == "UPLOAD" ]]
}

cat > "$LOG_FILE" <<EOF
Date: $(date)
Hostname: $(hostname)
Hypr Config: $HOME/.config/hypr

=========================================
SYSTEM INFORMATION
=========================================
$(inxi -Farz)

=========================================
DMESG
=========================================
$(sudo dmesg)

=========================================
JOURNALCTL (CURRENT BOOT, ERRORS ONLY)
=========================================
$(journalctl -b -p 4..1)

=========================================
INSTALLED PACKAGES
=========================================
$({ pacman -Qqe | xargs -r expac -S '%n %v (%r)' 2>/dev/null; comm -13 <(pacman -Sql | sort) <(pacman -Qqe | sort) | xargs -r expac -Q '%n %v (AUR)'; } | sort)
EOF

OPTIONS=("View log" "Save in current directory")
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
  OPTIONS=("Upload redacted log" "${OPTIONS[@]}")
fi

ACTION=$(printf '%s\n' "${OPTIONS[@]}" | fzf --prompt="Select action > " --height=5 --reverse)

case "$ACTION" in
  "Upload redacted log")
    if ! confirm_upload; then
      echo "Upload cancelled."
      exit 1
    fi
    redacted_log="$(mktemp "${TMPDIR:-/tmp}/hypr-debug-redacted.XXXXXX.log")"
    trap 'cleanup_redacted_log "$?"' EXIT
    redact_debug_log "${LOG_FILE}" "${redacted_log}"
    echo "Uploading redacted debug log to 0x0.st..."
    URL=$(curl --fail --silent --show-error -F "file=@${redacted_log}" -Fexpires=24 https://0x0.st)
    if [ $? -eq 0 ] && [ -n "$URL" ]; then
      echo "✓ Log uploaded successfully!"
      echo "Share this URL:"
      echo ""
      echo "  $URL"
      echo ""
      echo "This link will expire in 24 hours."
    else
      echo "Error: Failed to upload log file"
      exit 1
    fi
    ;;
  "View log")
    less "$LOG_FILE"
    ;;
  "Save in current directory")
    cp "$LOG_FILE" "./hypr-debug.log"
    echo "✓ Log saved to $(pwd)/hypr-debug.log"
    ;;
esac
