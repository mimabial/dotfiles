#!/usr/bin/env bash

set -euo pipefail

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$dotfiles_dir/stow.purge.sh"
"$dotfiles_dir/stow.link.sh"
"$dotfiles_dir/stow.services.sh"
