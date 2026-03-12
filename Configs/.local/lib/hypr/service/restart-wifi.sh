#!/usr/bin/env bash

set -euo pipefail

rfkill unblock wifi
rfkill list wifi
