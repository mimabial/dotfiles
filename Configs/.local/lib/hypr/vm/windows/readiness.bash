WINDOWS_RDP_RETRY_INTERVAL_SECONDS=2
WINDOWS_RDP_PROBE_TIMEOUT_SECONDS=2
WINDOWS_RDP_TIMEOUT_SECONDS=120
WINDOWS_RDP_REQUIRED_CONNECTIONS=2

windows_wait_for_rdp_port() {
  local deadline=$((SECONDS + WINDOWS_RDP_TIMEOUT_SECONDS))
  local consecutive_connections=0

  echo "Waiting for Windows VM to be ready..."
  while (( consecutive_connections < WINDOWS_RDP_REQUIRED_CONNECTIONS )); do
    if nc -z -w "${WINDOWS_RDP_PROBE_TIMEOUT_SECONDS}" "$WINDOWS_RDP_HOST" "$WINDOWS_RDP_PORT" 2>/dev/null; then
      consecutive_connections=$((consecutive_connections + 1))
      continue
    fi

    consecutive_connections=0
    if ((SECONDS + WINDOWS_RDP_RETRY_INTERVAL_SECONDS > deadline)); then
      echo "❌ Timeout waiting for RDP!"
      echo "   The VM might still be installing Windows."
      echo "   Check progress at: $WINDOWS_WEB_UI_URL"
      dunstify -r "${NOTIFY_ID_WINDOWS_VM}" -u critical -t "${NOTIFY_LONG_MS}" -i "computer" "Windows VM" "Timed out waiting for RDP. The VM may still be installing."
      exit 1
    fi
    sleep "${WINDOWS_RDP_RETRY_INTERVAL_SECONDS}"
  done
}
