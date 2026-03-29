#!/bin/bash

fc-list :spacing=100 -f "%{family[0]}\n" \
  | awk 'tolower($0) !~ /(^|[^[:alnum:]])(emoji|signwriting)([^[:alnum:]]|$)/' \
  | sort -u
