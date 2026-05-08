#!/usr/bin/env bash

set -euo pipefail

echo "Updating time..."
sudo systemctl restart systemd-timesyncd
