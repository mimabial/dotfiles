#!/usr/bin/env bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/managed/output.bash"
source "${BASH_SOURCE[0]%/*}/managed/manifest.bash"
# shellcheck source=/dev/null
source "${BASH_SOURCE[0]%/*}/../core/cli.bash"

hypr_help_guard "Usage: hyprshell service/list-managed-domains [domain...]
List managed domains and their manifest entries (all when none given)." "$@"

managed_print_domain_entry() {
  local -n listed_entry_ref="$1" listing_ref="$2"
  if [[ "${listed_entry_ref[domain]}" != "${listing_ref[current_domain]}" ]]; then
    [[ -z "${listing_ref[current_domain]}" ]] || printf '\n'
    printf '%s\n' "${listed_entry_ref[domain]}"
    listing_ref[current_domain]="${listed_entry_ref[domain]}"
  fi
  printf '  %-6s %-4s %-9s %-7s %s\n' "${listed_entry_ref[layer]}" "${listed_entry_ref[kind]}" "${listed_entry_ref[operation]}" "${listed_entry_ref[backup_policy]}" "${listed_entry_ref[relative_path]}"
}

declare -A domain_listing=([current_domain]="")
managed_visit_domains managed_print_domain_entry domain_listing "$@"
