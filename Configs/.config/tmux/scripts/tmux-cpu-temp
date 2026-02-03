#!/usr/bin/env bash
sensors -u coretemp-isa-0000 |
  awk '/temp[2-9][0-9]*_input:/ { sum += $2; n++ }
         END { if (n) printf "%d°C", sum/n; else printf "N/A" }'
