#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)"

source "${SERVICE_DIR}/service.lib.bash"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
hypr_service_die() { printf 'die: %s\n' "$1" >&2; return 42; }

test_policies_that_back_up() {
  hypr_service_should_back_up always file || fail "always must back up"
  hypr_service_should_back_up changed file || fail "changed must back up"
}

test_policy_that_does_not() {
  if hypr_service_should_back_up never file; then fail "never must not back up"; fi
}

# An unknown policy must abort rather than silently skip the backup.
test_unknown_policy_aborts() {
  local out="" rc=0
  out="$(hypr_service_should_back_up bogus tree 2>&1)" || rc=$?
  (( rc == 42 )) || fail "unknown policy should die, got rc=${rc}"
  [[ "${out}" == *"Unsupported backup policy for tree: bogus"* ]] \
    || fail "error must name the kind and the policy: ${out}"
}

# The file and tree messages come from one place now, so they cannot drift.
test_kind_appears_in_message() {
  local out=""
  out="$(hypr_service_should_back_up bogus file 2>&1)" || true
  [[ "${out}" == *"for file: bogus"* ]] || fail "file kind not reported: ${out}"
}

test_parser_outputs() {
  local -A options=()
  local -a args=()
  hypr_service_parse_refresh_args options args -n -q --diff --backup-label daily -- config/file
  [[ "${options[dry_run]}:${options[quiet]}:${options[show_diff]}:${options[backup_label]}" == 1:1:1:daily ]] || fail "parsed options"
  [[ "${args[*]}" == config/file ]] || fail "parsed path"
  hypr_service_apply_cli_env "${options[dry_run]}" "${options[backup_label]}"
  [[ "${HYPR_SERVICE_DRY_RUN}:${HYPR_SERVICE_BACKUP_LABEL}" == 1:daily ]] || fail "applied options"
}

test_policies_that_back_up
test_policy_that_does_not
test_unknown_policy_aborts
test_kind_appears_in_message
test_parser_outputs
