#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/lib/timing.sh
. "$project_root/src/lib/timing.sh"
# shellcheck source=../../src/lib/input.sh
. "$project_root/src/lib/input.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if test "$actual" != "$expected"; then
    printf 'FAIL: %s expected %s got %s\n' "$label" "$expected" "$actual" >&2
    return 1
  fi

  printf 'PASS: %s = %s\n' "$label" "$actual"
}

assert_equal "5" "$(parse_duration_ms 5ms)" "parse_duration_ms 5ms"
assert_equal "30" "$(parse_duration_ms 30ms)" "parse_duration_ms 30ms"
assert_equal "500" "$(parse_duration_ms 500ms)" "parse_duration_ms 500ms"
assert_equal "1000" "$(parse_duration_ms 1s)" "parse_duration_ms 1s"
assert_equal "1100" "$(parse_duration_ms 1s100ms)" "parse_duration_ms 1s100ms"
assert_equal "2000" "$(parse_duration_ms 2s)" "parse_duration_ms 2s"
assert_equal "975" "$(parse_duration_ms 975ms)" "parse_duration_ms 975ms"

MACRO_INPUT_MODE="${MACRO_INPUT_MODE:-dry-run}"

input_sleep 5ms
move_mouse 100 200
click_point 100 200
keydown w
keyup w
tap_key e
release_all_inputs

if MACRO_INPUT_MODE=live MACRO_LIVE_INPUT_ALLOWED= input_require_live_allowed; then
  printf 'FAIL: live mode was not blocked without MACRO_LIVE_INPUT_ALLOWED=1\n' >&2
  exit 1
fi

printf 'PASS: live mode blocked without MACRO_LIVE_INPUT_ALLOWED=1\n'
