#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/modules/place_runner.sh
. "$project_root/src/modules/place_runner.sh"

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

write_valid_points() {
  local file="$1"

  {
    printf 'BASE_TELEPORT_BUTTON_X=398\n'
    printf 'BASE_TELEPORT_BUTTON_Y=33\n'
    printf 'PACK_CLICK_POINT_X=88\n'
    printf 'PACK_CLICK_POINT_Y=563\n'
    printf 'PLACE_HOLD_POINT_X=435\n'
    printf 'PLACE_HOLD_POINT_Y=391\n'
  } > "$file"
}

unset_point() {
  local file="$1"
  local point="$2"

  {
    printf '%s_X=\n' "$point"
    printf '%s_Y=\n' "$point"
  } >> "$file"
}

write_valid_timing() {
  local file="$1"

  {
    printf 'BASE_PRESS_COUNT_NORMAL=1\n'
    printf 'BASE_PRESS_DELAY=5ms\n'
    printf 'POST_BASE_WAIT=5ms\n'
    printf 'PLACE_FORWARD_DURATION=1s100ms\n'
    printf 'PLACE_LEFT_DURATION=975ms\n'
    printf 'PLACE_CLICK_INTERVAL=100ms\n'
    printf 'POST_PLACE_WAIT=1ms\n'
  } > "$file"
}

load_temp_context() {
  local points_file="$1"
  local timing_file="$2"

  points_load "$points_file"
  timing_load "$timing_file"
}

expect_preflight_fails() {
  local label="$1"
  local expected="$2"
  local output

  if output="$(place_runner_preflight 2>&1)"; then
    printf 'FAIL: %s preflight passed unexpectedly\n' "$label" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  assert_contains "$output" "$expected" "$label"
}

expect_preflight_passes() {
  local label="$1"

  if ! place_runner_preflight >/dev/null; then
    printf 'FAIL: %s preflight failed\n' "$label" >&2
    return 1
  fi

  printf 'PASS: %s preflight passed\n' "$label"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

points_file="$tmp_dir/points.conf"
timing_file="$tmp_dir/timing.conf"

printf 'CASE: missing base point fails\n'
write_valid_points "$points_file"
unset_point "$points_file" BASE_TELEPORT_BUTTON
write_valid_timing "$timing_file"
load_temp_context "$points_file" "$timing_file"
expect_preflight_fails "missing base point" "BASE_TELEPORT_BUTTON"

printf 'CASE: missing pack point fails\n'
write_valid_points "$points_file"
unset_point "$points_file" PACK_CLICK_POINT
write_valid_timing "$timing_file"
load_temp_context "$points_file" "$timing_file"
expect_preflight_fails "missing pack point" "PACK_CLICK_POINT"

printf 'CASE: missing place hold point fails\n'
write_valid_points "$points_file"
unset_point "$points_file" PLACE_HOLD_POINT
write_valid_timing "$timing_file"
load_temp_context "$points_file" "$timing_file"
expect_preflight_fails "missing place hold point" "PLACE_HOLD_POINT"

printf 'CASE: zero base press count is allowed\n'
write_valid_points "$points_file"
write_valid_timing "$timing_file"
{
  printf 'BASE_PRESS_COUNT_NORMAL=0\n'
  printf 'BASE_PRESS_DELAY=5ms\n'
  printf 'POST_BASE_WAIT=5ms\n'
  printf 'PLACE_FORWARD_DURATION=1s100ms\n'
  printf 'PLACE_LEFT_DURATION=975ms\n'
  printf 'PLACE_CLICK_INTERVAL=100ms\n'
  printf 'POST_PLACE_WAIT=1ms\n'
} > "$timing_file"
load_temp_context "$points_file" "$timing_file"
expect_preflight_passes "zero base count"

PLACE_RUNNER_POINTS_FILE="$points_file"
PLACE_RUNNER_TIMING_FILE="$timing_file"
MACRO_INPUT_MODE=dry-run
output="$(place_runner_run 2>&1)"
assert_contains "$output" "TRACE place-runner base_teleport count=0" "zero base count runner trace"
assert_not_contains "$output" "TRACE place-runner click point=BASE_TELEPORT_BUTTON" "zero base count runner trace"

printf 'CASE: zero placement duration fails\n'
write_valid_points "$points_file"
write_valid_timing "$timing_file"
{
  printf 'BASE_PRESS_COUNT_NORMAL=1\n'
  printf 'BASE_PRESS_DELAY=5ms\n'
  printf 'POST_BASE_WAIT=5ms\n'
  printf 'PLACE_FORWARD_DURATION=0ms\n'
  printf 'PLACE_LEFT_DURATION=975ms\n'
  printf 'PLACE_CLICK_INTERVAL=100ms\n'
  printf 'POST_PLACE_WAIT=1ms\n'
} > "$timing_file"
load_temp_context "$points_file" "$timing_file"
expect_preflight_fails "zero placement duration" "PLACE_FORWARD_DURATION"

printf 'PASS: place-runner negative dry run completed\n'
