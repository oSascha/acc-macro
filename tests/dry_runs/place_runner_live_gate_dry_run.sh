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

printf 'CASE: direct live invocation blocked with no gates\n'
if output="$(env -u MACRO_INPUT_MODE -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_RUNNER_LIVE_CONFIRM "$project_root/src/modules/place_runner.sh" --live 2>&1)"; then
  printf 'FAIL: direct live invocation passed with no gates\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "live place runner blocked" "direct no-gate live block"
assert_not_contains "$output" "TRACE place-runner start" "direct no-gate live block"

printf 'CASE: direct live invocation blocked with only MACRO_INPUT_MODE=live\n'
if output="$(env -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_RUNNER_LIVE_CONFIRM MACRO_INPUT_MODE=live "$project_root/src/modules/place_runner.sh" --live 2>&1)"; then
  printf 'FAIL: direct live invocation passed with only input mode gate\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "live place runner blocked" "direct partial-gate live block"
assert_not_contains "$output" "TRACE place-runner start" "direct partial-gate live block"

printf 'CASE: macroctl live command blocked with no gates\n'
if output="$(env -u MACRO_INPUT_MODE -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_RUNNER_LIVE_CONFIRM "$project_root/bin/macroctl" live place-runner 2>&1)"; then
  printf 'FAIL: macroctl live invocation passed with no gates\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "live place runner blocked" "macroctl no-gate live block"
assert_not_contains "$output" "TRACE place-runner start" "macroctl no-gate live block"

printf 'CASE: dry-run still works\n'
output="$(env -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_RUNNER_LIVE_CONFIRM "$project_root/bin/macroctl" dry-run place-runner 2>&1)"
assert_contains "$output" "TRACE place-runner start" "dry-run still starts"
assert_contains "$output" "TRACE place-runner complete" "dry-run still completes"

printf 'PASS: place-runner live gate dry run completed\n'
