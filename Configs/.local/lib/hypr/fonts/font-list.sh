#!/usr/bin/env bash

set -euo pipefail

fc-list :spacing=100 -f "%{family[0]}\n" \
  | awk 'tolower($0) !~ /(^|[^[:alnum:]])(emoji|signwriting)([^[:alnum:]]|$)/' \
  | awk '$0 !~ /(^| )Mono($| )/' \
  | sort -u
