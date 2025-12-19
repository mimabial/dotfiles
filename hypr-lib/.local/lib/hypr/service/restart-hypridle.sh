#!/usr/bin/env bash

set -euo pipefail

systemctl --user restart hyprland-hypridle.service >/dev/null 2>&1 || true
