#!/bin/bash

# Parse options: -d/--download, -u/--upload, or both (default)
MODE="both"
case "$1" in
  -u | --upload) MODE="upload" ;;
  -d | --download) MODE="download" ;;
  "") MODE="both" ;;
  *)
    echo '{"text":"ERR","tooltip":"Invalid option. Use -d, -u, or none"}'
    exit 1
    ;;
esac

STATE_FILE="/tmp/waybar-netspeed-$USER"
INTERFACE=$(ip route | awk '/^default/ {print $5; exit}')

# If no network interface is active
if [ -z "$INTERFACE" ]; then
  echo '{"text":"00\n00\nKB\n/s","tooltip":"Not Connected"}'
  exit 0
fi

RX_NOW=$(<"/sys/class/net/$INTERFACE/statistics/rx_bytes")
TX_NOW=$(<"/sys/class/net/$INTERFACE/statistics/tx_bytes")
TIME_NOW=$(date +%s%N)

if [ -f "$STATE_FILE" ]; then
  read -r PREV_INTERFACE RX_PREV TX_PREV TIME_PREV <"$STATE_FILE"

  # Reset if interface changed
  if [ "$PREV_INTERFACE" != "$INTERFACE" ]; then
    RX_BYTES_PER_SEC=0
    TX_BYTES_PER_SEC=0
  else
    TIME_DIFF=$(awk -v now=$TIME_NOW -v prev=$TIME_PREV 'BEGIN {print (now - prev) / 1e9}')
    RX_BYTES_PER_SEC=$(awk -v now=$RX_NOW -v prev=$RX_PREV -v dt=$TIME_DIFF 'BEGIN {
            if (dt > 0) printf "%.0f", (now - prev) / dt;
            else print 0;
        }')
    TX_BYTES_PER_SEC=$(awk -v now=$TX_NOW -v prev=$TX_PREV -v dt=$TIME_DIFF 'BEGIN {
            if (dt > 0) printf "%.0f", (now - prev) / dt;
            else print 0;
        }')
  fi
else
  RX_BYTES_PER_SEC=0
  TX_BYTES_PER_SEC=0
fi

echo "$INTERFACE $RX_NOW $TX_NOW $TIME_NOW" >"$STATE_FILE"

# Format speed display based on mode
if [ "$MODE" = "both" ]; then
  # Format both download and upload with empty line between
  JSON_TEXT=$(awk -v down=$RX_BYTES_PER_SEC -v up=$TX_BYTES_PER_SEC 'BEGIN {
        # Download speed
        down_unit = "K";
        down_speed = down / 1024;
        if (down >= 1048576) { down_unit = "M"; down_speed = down / 1048576; }
        if (down >= 1073741824) { down_unit = "G"; down_speed = down / 1073741824; }
        if (down_speed > 99.99) down_speed = 99.99;
        down_int = int(down_speed);
        if (down_int > 99) down_int = 99;
        down_dec = int((down_speed - down_int) * 100);
        
        # Upload speed
        up_unit = "K";
        up_speed = up / 1024;
        if (up >= 1048576) { up_unit = "M"; up_speed = up / 1048576; }
        if (up >= 1073741824) { up_unit = "G"; up_speed = up / 1073741824; }
        if (up_speed > 99.99) up_speed = 99.99;
        up_int = int(up_speed);
        if (up_int > 99) up_int = 99;
        up_dec = int((up_speed - up_int) * 100);
        
        printf "{\"text\":\"󰇚:\\n%02d%s\\n%02dB\\n󰕒:\\n%02d%s\\n%02dB\"}", down_int, down_unit, down_dec, up_int, up_unit, up_dec;
    }')

elif [ "$MODE" = "download" ]; then
  DISPLAY_BYTES=$RX_BYTES_PER_SEC

  JSON_TEXT=$(awk -v b=$DISPLAY_BYTES 'BEGIN {
        unit = "KB\\n/s";
        speed = b / 1024;
        if (b >= 1048576) { unit = "MB\\n/s"; speed = b / 1048576; }
        if (b >= 1073741824) { unit = "GB\\n/s"; speed = b / 1073741824; }
        if (speed > 99.99) speed = 99.99;
        int_part = int(speed);
        if (int_part > 99) int_part = 99;
        dec_part = int((speed - int_part) * 100);
        printf "{\"text\":\"%02d\\n%02d\\n%s\"}", int_part, dec_part, unit;
    }')

else # upload mode
  DISPLAY_BYTES=$TX_BYTES_PER_SEC

  JSON_TEXT=$(awk -v b=$DISPLAY_BYTES 'BEGIN {
        unit = "KB\\n/s";
        speed = b / 1024;
        if (b >= 1048576) { unit = "MB\\n/s"; speed = b / 1048576; }
        if (b >= 1073741824) { unit = "GB\\n/s"; speed = b / 1073741824; }
        if (speed > 99.99) speed = 99.99;
        int_part = int(speed);
        if (int_part > 99) int_part = 99;
        dec_part = int((speed - int_part) * 100);
        printf "{\"text\":\"%02d\\n%02d\\n%s\"}", int_part, dec_part, unit;
    }')
fi

# Format both speeds for tooltip
DOWN_SPEED=$(awk -v b=$RX_BYTES_PER_SEC 'BEGIN {
    if (b >= 1073741824) printf "%.2f GB/s", b / 1073741824;
    else if (b >= 1048576) printf "%.2f MB/s", b / 1048576;
    else printf "%.2f KB/s", b / 1024;
}')

UP_SPEED=$(awk -v b=$TX_BYTES_PER_SEC 'BEGIN {
    if (b >= 1073741824) printf "%.2f GB/s", b / 1073741824;
    else if (b >= 1048576) printf "%.2f MB/s", b / 1048576;
    else printf "%.2f KB/s", b / 1024;
}')

IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
TOOLTIP=$(printf 'Down: %s\nUp: %s' "$DOWN_SPEED" "$UP_SPEED" | jq -Rs .)

echo "${JSON_TEXT::-1},\"tooltip\":$TOOLTIP}"
