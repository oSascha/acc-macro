#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s missing %s\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    return 1
  fi

  printf 'PASS: %s contains %s\n' "$label" "$needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'FAIL: %s unexpectedly contained %s\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    return 1
  fi

  printf 'PASS: %s does not contain %s\n' "$label" "$needle"
}

module="$project_root/src/modules/live_cycle_runner.sh"

run_dry_expect_fail() {
  local label="$1"
  shift
  local output

  if output="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" "$module" --dry-run "$@" 2>&1)"; then
    printf 'FAIL: %s passed unexpectedly\n' "$label" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  printf 'PASS: %s failed as expected\n' "$label"
  printf '%s\n' "$output"
}

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input allowance must not be enabled for this negative test\n' >&2
  exit 1
fi
printf 'PASS: live input allowance is not enabled\n'

# cycles 0 fails
out="$(run_dry_expect_fail "cycles 0" --cycles 0)"
assert_contains "$out" "cycles must be at least 1: 0" "cycles 0 message"

# cycles 4 fails (above the max of 3)
out="$(run_dry_expect_fail "cycles 4" --cycles 4)"
assert_contains "$out" "cycles 4 exceeds max 3" "cycles 4 message"

# malformed cycles fails
out="$(run_dry_expect_fail "malformed cycles" --cycles abc)"
assert_contains "$out" "cycles must be a positive integer: abc" "malformed cycles message"

# cycles 999 fails (explicit contract rejection)
out="$(run_dry_expect_fail "cycles 999" --cycles 999)"
assert_contains "$out" "cycles 999 exceeds max 3" "cycles 999 message"

# bad cycles still fail when --no-potions is supplied (flag parses, cycles reject)
out="$(run_dry_expect_fail "no-potions with bad cycles" --no-potions --cycles 0)"
assert_contains "$out" "cycles must be at least 1: 0" "no-potions bad cycles message"

# unknown option fails
out="$(run_dry_expect_fail "unknown option" --bogus)"
assert_contains "$out" "Usage:" "unknown option usage"

# direct --live without gates fails before any input trace
printf 'CASE: direct --live without gates fails before any trace\n'
if out="$(env -u MACRO_INPUT_MODE -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_LIVE_CYCLE_RUNNER_CONFIRM "$module" --live 2>&1)"; then
  printf 'FAIL: direct --live passed with no gates\n' >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
assert_contains "$out" "live cycle runner blocked" "direct live block message"
assert_not_contains "$out" "TRACE live-cycle-runner start" "direct live block has no start trace"
assert_not_contains "$out" "TRACE input" "direct live block has no input trace"
assert_not_contains "$out" "xdotool" "direct live block has no xdotool"

# direct --live with only MACRO_INPUT_MODE=live still blocked
printf 'CASE: direct --live with partial gates fails before any trace\n'
if out="$(env -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_LIVE_CYCLE_RUNNER_CONFIRM MACRO_INPUT_MODE=live "$module" --live 2>&1)"; then
  printf 'FAIL: direct --live passed with partial gates\n' >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
assert_contains "$out" "live cycle runner blocked" "partial gate block message"
assert_not_contains "$out" "TRACE live-cycle-runner start" "partial gate block has no start trace"
assert_not_contains "$out" "TRACE input" "partial gate block has no input trace"
assert_not_contains "$out" "xdotool" "partial gate block has no xdotool"

# sourced function with MACRO_INPUT_MODE=live and no gates fails before any input trace
printf 'CASE: sourced run with live mode and no gates fails before any trace\n'
if out="$(
  env -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_LIVE_CYCLE_RUNNER_CONFIRM bash -c '
    set -euo pipefail
    project_root="$1"
    . "$project_root/src/modules/live_cycle_runner.sh"
    MACRO_INPUT_MODE=live live_cycle_runner_run 1 0
  ' _ "$project_root" 2>&1
)"; then
  printf 'FAIL: sourced live run passed with no gates\n' >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
assert_contains "$out" "live cycle runner blocked" "sourced live block message"
assert_not_contains "$out" "TRACE live-cycle-runner start" "sourced live block has no start trace"
assert_not_contains "$out" "TRACE input" "sourced live block has no input trace"
assert_not_contains "$out" "xdotool" "sourced live block has no xdotool"

printf 'PASS: live-cycle-runner negative dry run completed\n'
