#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)"

source "${SERVICE_DIR}/managed/init.bash"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
managed_fail() { printf 'die: %s\n' "$1" >&2; return 42; }

test_policies_that_back_up() {
  managed_backup_policy_is_enabled always file || fail "always must back up"
  managed_backup_policy_is_enabled changed file || fail "changed must back up"
}

test_policy_that_does_not() {
  if managed_backup_policy_is_enabled never file; then fail "never must not back up"; fi
}

# An unknown policy must abort rather than silently skip the backup.
test_unknown_policy_aborts() {
  local out="" rc=0
  out="$(managed_backup_policy_is_enabled bogus tree 2>&1)" || rc=$?
  (( rc == 42 )) || fail "unknown policy should die, got rc=${rc}"
  [[ "${out}" == *"Unsupported backup policy for tree: bogus"* ]] \
    || fail "error must name the kind and the policy: ${out}"
}

# The file and tree messages come from one place now, so they cannot drift.
test_kind_appears_in_message() {
  local out=""
  out="$(managed_backup_policy_is_enabled bogus file 2>&1)" || true
  [[ "${out}" == *"for file: bogus"* ]] || fail "file kind not reported: ${out}"
}

test_parser_outputs() {
  local -A options=()
  local -a args=()
  managed_parse_options_into options args -n -q --diff --backup-label daily -- config/file
  [[ "${options[dry_run]}:${options[quiet]}:${options[show_diff]}:${options[backup_label]}" == 1:1:1:daily ]] || fail "parsed options"
  [[ "${args[*]}" == config/file ]] || fail "parsed path"
  [[ -z "${options[backup_root]}" ]] || fail "backup root must start empty"
}

test_policies_that_back_up
test_policy_that_does_not
test_unknown_policy_aborts
test_kind_appears_in_message
test_parser_outputs

test_backup_root_reused() (
  local fixture_root first_root
  fixture_root="$(mktemp -d)"
  trap 'rm -rf "${fixture_root}"' EXIT
  local XDG_CONFIG_HOME="${fixture_root}/config"
  date() { printf x >>"${fixture_root}/date.calls"; printf '20261009_120000\n'; }
  local -A run=([backup_label]=test [backup_root]="") path=()
  printf 'first contents\n' >"${fixture_root}/first"
  path[target]="${fixture_root}/first"
  managed_back_up_path_into path run
  first_root="${run[backup_root]}"
  [[ -n "${first_root}" && "$(<"${path[backup_path]}")" == 'first contents' ]] || fail "first backup"
  printf 'second contents\n' >"${fixture_root}/second"
  path[target]="${fixture_root}/second"
  managed_back_up_path_into path run
  [[ "${run[backup_root]}" == "${first_root}" && "$(<"${path[backup_path]}")" == 'second contents' ]] || fail "shared backup root"
  [[ "$(<"${fixture_root}/date.calls")" == x ]] || fail "timestamp must be generated once"
)

test_backup_root_reused
