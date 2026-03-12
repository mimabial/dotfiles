#!/usr/bin/env bash

set -euo pipefail

rfkill unblock bluetooth
rfkill list bluetooth
