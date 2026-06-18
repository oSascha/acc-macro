#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/lib/input.sh
. "$project_root/src/lib/input.sh"

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

expect_fails() {
  local label="$1"
  shift

  if output="$("$@" 2>&1)"; then
    printf 'FAIL: %s passed unexpectedly\n' "$label" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  printf 'PASS: %s failed as expected\n' "$label"
}

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input allowance must not be enabled for this dry-run test\n' >&2
  exit 1
fi
printf 'PASS: live input allowance is not enabled\n'

if ! declare -F input_click_current_burst >/dev/null; then
  printf 'FAIL: input_click_current_burst function is missing\n' >&2
  exit 1
fi
printf 'PASS: input_click_current_burst function exists\n'

output="$(MACRO_INPUT_MODE=dry-run input_click_current_burst 300 1 2>&1)"
assert_contains "$output" "TRACE input dry-run click_current_burst count=300 delay_ms=1 button=1" "valid burst trace"
assert_contains "$output" "count=300 delay_ms=1" "valid burst count and delay"

expect_fails "count zero" env MACRO_INPUT_MODE=dry-run bash -c '
  set -euo pipefail
  project_root="$1"
  . "$project_root/src/lib/input.sh"
  input_click_current_burst 0 1
' _ "$project_root"

expect_fails "negative count" env MACRO_INPUT_MODE=dry-run bash -c '
  set -euo pipefail
  project_root="$1"
  . "$project_root/src/lib/input.sh"
  input_click_current_burst -1 1
' _ "$project_root"

expect_fails "malformed count" env MACRO_INPUT_MODE=dry-run bash -c '
  set -euo pipefail
  project_root="$1"
  . "$project_root/src/lib/input.sh"
  input_click_current_burst abc 1
' _ "$project_root"

expect_fails "count above max" env MACRO_INPUT_MODE=dry-run bash -c '
  set -euo pipefail
  project_root="$1"
  . "$project_root/src/lib/input.sh"
  input_click_current_burst 1501 1
' _ "$project_root"

expect_fails "malformed delay" env MACRO_INPUT_MODE=dry-run bash -c '
  set -euo pipefail
  project_root="$1"
  . "$project_root/src/lib/input.sh"
  input_click_current_burst 10 bad
' _ "$project_root"

expect_fails "delay above max" env MACRO_INPUT_MODE=dry-run bash -c '
  set -euo pipefail
  project_root="$1"
  . "$project_root/src/lib/input.sh"
  input_click_current_burst 10 1001
' _ "$project_root"

printf 'PASS: fast click burst dry run completed\n'
