#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLONE_DIR="${repo_dir}"

if [ -d "${repo_dir}/.git" ]; then
  git -C "${repo_dir}" pull --ff-only
fi

exec "${repo_dir}/Scripts/install.sh" -r -s
