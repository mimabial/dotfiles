#!/usr/bin/env bash

set -euo pipefail

fc-list :spacing=100 -f "%{family[0]}\n" \
  | awk 'tolower($0) !~ /(^|[^[:alnum:]])(emoji|signwriting)([^[:alnum:]]|$)/' \
  | sort -u \
  | awk '
      {
        fonts[++count] = $0
        present[$0] = 1
      }
      END {
        for (i = 1; i <= count; i++) {
          font = fonts[i]
          if (font ~ / Nerd Font Mono$/) {
            base_font = font
            sub(/ Mono$/, "", base_font)
            if (base_font in present) {
              continue
            }
          }
          print font
        }
      }
    '
