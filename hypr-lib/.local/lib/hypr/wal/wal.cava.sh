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

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Ensure color file exists
if [ ! -f "$CAVA_DCOL" ]; then
  echo "Color file not found: $CAVA_DCOL"
  exit 1
fi

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

    echo "Updated Cava color section in $CAVA_CONF"
  fi
fi
