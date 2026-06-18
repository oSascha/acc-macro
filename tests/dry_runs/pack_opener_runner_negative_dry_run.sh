#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/modules/pack_opener_runner.sh
. "$project_root/src/modules/pack_opener_runner.sh"

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
    printf 'POST_SECOND_BASE_WAIT=1ms\n'
  } > "$file"
}

write_valid_plan() {
  local file="$1"

  {
    printf 'POTION_PLAN_ENABLED=0\n\n'
    printf 'POTION_2_MIN_ENABLED=0\n'
    printf 'POTION_2_MIN_USE_AMOUNT=0\n'
    printf 'POTION_2_MIN_INVENTORY=0\n\n'
    printf 'POTION_6_MIN_ENABLED=0\n'
    printf 'POTION_6_MIN_USE_AMOUNT=0\n'
    printf 'POTION_6_MIN_INVENTORY=0\n\n'
    printf 'POTION_15_MIN_ENABLED=0\n'
    printf 'POTION_15_MIN_USE_AMOUNT=0\n'
    printf 'POTION_15_MIN_INVENTORY=0\n\n'
    printf 'POTION_NAV_CLICK_INTERVAL=30ms\n'
    printf 'POTION_CLICK_INTERVAL=50ms\n\n'
    printf 'CLOSE_INVENTORY=1\n'
  } > "$file"
}

load_temp_context() {
  local points_file="$1"
  local timing_file="$2"
  local plan_file="$3"

  points_load "$points_file"
  timing_load "$timing_file"
  potion_plan_load "$plan_file"
}

expect_command_fails() {
  local label="$1"
  local expected="$2"
  shift 2
  local output

  if output="$("$@" 2>&1)"; then
    printf 'FAIL: %s passed unexpectedly\n' "$label" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  assert_contains "$output" "$expected" "$label"
  assert_not_contains "$output" "TRACE pack-opener-runner start" "$label"
}

expect_preflight_fails() {
  local label="$1"
  local expected="$2"
  local output

  if output="$(pack_opener_runner_preflight 2>&1)"; then
    printf 'FAIL: %s preflight passed unexpectedly\n' "$label" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  assert_contains "$output" "$expected" "$label"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

points_file="$tmp_dir/points.conf"
timing_file="$tmp_dir/timing.conf"
plan_file="$tmp_dir/potion_plan.conf"

printf 'CASE: cycle count 0 fails\n'
expect_command_fails "cycles zero" "cycles" env MACRO_INPUT_MODE=dry-run "$project_root/src/modules/pack_opener_runner.sh" --dry-run --cycles 0

printf 'CASE: cycle count above max fails\n'
expect_command_fails "cycles above max" "max" env MACRO_INPUT_MODE=dry-run "$project_root/src/modules/pack_opener_runner.sh" --dry-run --cycles 4

printf 'CASE: malformed cycle count fails\n'
expect_command_fails "cycles malformed" "cycles" env MACRO_INPUT_MODE=dry-run "$project_root/src/modules/pack_opener_runner.sh" --dry-run --cycles abc

printf 'CASE: missing return-to-base point fails\n'
write_valid_points "$points_file"
unset_point "$points_file" BASE_TELEPORT_BUTTON
write_valid_timing "$timing_file"
write_valid_plan "$plan_file"
load_temp_context "$points_file" "$timing_file" "$plan_file"
expect_preflight_fails "missing return-to-base point" "BASE_TELEPORT_BUTTON"

printf 'CASE: invalid return-to-base timing fails\n'
write_valid_points "$points_file"
{
  printf 'BASE_PRESS_COUNT_NORMAL=1\n'
  printf 'BASE_PRESS_DELAY=5ms\n'
  printf 'POST_SECOND_BASE_WAIT=bad\n'
} > "$timing_file"
write_valid_plan "$plan_file"
load_temp_context "$points_file" "$timing_file" "$plan_file"
expect_preflight_fails "invalid return-to-base timing" "POST_SECOND_BASE_WAIT"

printf 'CASE: sourced function rejects live input mode\n'
if output="$(env -u MACRO_LIVE_INPUT_ALLOWED bash -c '
  set -euo pipefail
  project_root="$1"
  . "$project_root/src/modules/pack_opener_runner.sh"
  MACRO_INPUT_MODE=live pack_opener_runner_run 2
' _ "$project_root" 2>&1)"; then
  printf 'FAIL: sourced function live mode passed unexpectedly\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "only supports MACRO_INPUT_MODE=dry-run" "sourced live mode"
assert_not_contains "$output" "TRACE pack-opener-runner start" "sourced live mode"
assert_not_contains "$output" "xdotool" "sourced live mode"

printf 'CASE: direct live remains unavailable\n'
if output="$(env -u MACRO_INPUT_MODE -u MACRO_LIVE_INPUT_ALLOWED "$project_root/src/modules/pack_opener_runner.sh" --live 2>&1)"; then
  printf 'FAIL: live invocation passed unexpectedly\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "live Pack Opener runner is unavailable" "direct live unavailable"
assert_not_contains "$output" "TRACE pack-opener-runner start" "direct live unavailable"
assert_not_contains "$output" "xdotool" "direct live unavailable"

printf 'PASS: pack-opener-runner negative dry run completed\n'
