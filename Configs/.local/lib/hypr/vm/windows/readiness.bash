WINDOWS_RDP_RETRY_INTERVAL_SECONDS=2
WINDOWS_RDP_PROBE_TIMEOUT_SECONDS=2
WINDOWS_RDP_TIMEOUT_SECONDS=120

windows_wait_for_rdp_port() {
  local deadline=$((SECONDS + WINDOWS_RDP_TIMEOUT_SECONDS))

  echo "Waiting for Windows VM to be ready..."
  until nc -z -w "${WINDOWS_RDP_PROBE_TIMEOUT_SECONDS}" "$WINDOWS_RDP_HOST" "$WINDOWS_RDP_PORT" 2>/dev/null; do
    if ((SECONDS + WINDOWS_RDP_RETRY_INTERVAL_SECONDS > deadline)); then
      echo "❌ Timeout waiting for RDP!"
      echo "   The VM might still be installing Windows."
      echo "   Check progress at: $WINDOWS_WEB_UI_URL"
      dunstify -r "${NOTIFY_ID_WINDOWS_VM}" -u critical -t "${NOTIFY_LONG_MS}" -i "computer" "Windows VM" "Timed out waiting for RDP. The VM may still be installing."
      return 1
    fi
    sleep "${WINDOWS_RDP_RETRY_INTERVAL_SECONDS}"
  done
}
