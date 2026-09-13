#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)"

extract() { awk -v fn="$1" '$0 ~ "^"fn"\\(\\) \\{" {p=1} p {print; if ($0 == "}") exit}' \
  "${SERVICE_DIR}/service.lib.bash"; }
eval "$(extract hypr_service_should_back_up)"

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

test_policies_that_back_up
test_policy_that_does_not
test_unknown_policy_aborts
test_kind_appears_in_message
