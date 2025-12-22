#!/usr/bin/env bash

# shellcheck source=/home/rifle/.local/bin/hyprshell
# shellcheck disable=SC1091
if ! source "$(which hyprshell)"; then
  echo "[pywal16] code :: Error: hyprshell not found."
  exit 1
fi

confDir="$XDG_CONFIG_HOME"
cacheDir="$XDG_CACHE_HOME"
cvaDir="${confDir}/cava"
CAVA_CONF="${cvaDir}/config"
CAVA_DCOL="${cacheDir}/wal/colors-cava"
hashFile="${XDG_RUNTIME_DIR:-/tmp}/wal-cava-hash"

# Ensure color file exists
if [ ! -f "$CAVA_DCOL" ]; then
  exit 0
fi

# Change detection: skip if colors unchanged
input_hash=$(md5sum "$CAVA_DCOL" 2>/dev/null | cut -d' ' -f1)
if [[ -f "$hashFile" && "$(cat "$hashFile" 2>/dev/null)" == "$input_hash" ]]; then
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if pkg_installed cava; then
  if [[ ! -d "${cvaDir}" ]]; then
    print_log -sec "wallbash" -warn "Not initialized" "cava config directory not found. Try running cava first."
  else
    # Replace [color] section in-place, preserving its position
    # If no [color] section exists, append it at the end
    awk -v color_file="$CAVA_DCOL" '
      BEGIN { found=0 }
      /^[[:space:]]*\[color\]/ {
        # Found [color] section, insert new colors
        found=1
        while ((getline line < color_file) > 0) {
          print line
        }
        close(color_file)
        incolor=1
        next
      }
      incolor && /^[[:space:]]*\[/ {
        # End of [color] section, resume normal output
        incolor=0
      }
      !incolor {
        print
      }
      END {
        # If no [color] section was found, append it
        if (!found) {
          print ""
          while ((getline line < color_file) > 0) {
            print line
          }
          close(color_file)
        }
      }
    ' "$CAVA_CONF" >"$TMP"

    # Move final file in place
    mv "$TMP" "$CAVA_CONF"
    trap - EXIT

    # Save hash for next run
    echo "$input_hash" > "$hashFile"

    echo "Updated Cava color section in $CAVA_CONF"
  fi
fi
