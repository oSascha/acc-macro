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

assert_equals() {
  local actual="$1"
  local expected="$2"
  local label="$3"

  if test "$actual" != "$expected"; then
    printf 'FAIL: %s expected %s got %s\n' "$label" "$expected" "$actual" >&2
    return 1
  fi

  printf 'PASS: %s equals %s\n' "$label" "$expected"
}

write_points() {
  local file="$1"

  {
    printf 'BASE_TELEPORT_BUTTON_X=398\n'
    printf 'BASE_TELEPORT_BUTTON_Y=33\n'
    printf 'PACK_CLICK_POINT_X=88\n'
    printf 'PACK_CLICK_POINT_Y=563\n'
    printf 'PLACE_HOLD_POINT_X=88\n'
    printf 'PLACE_HOLD_POINT_Y=563\n'
  } > "$file"
}

write_timing() {
  local file="$1"
  local live_click="${2:-}"
  local live_e="${3:-}"
  local burst_delay="${4:-}"
  local burst_margin="${5:-}"

  {
    printf 'BASE_PRESS_COUNT_NORMAL=1\n'
    printf 'BASE_PRESS_DELAY=5ms\n'
    printf 'POST_BASE_WAIT=5ms\n'
    printf 'PLACE_FORWARD_DURATION=1s100ms\n'
    printf 'PLACE_LEFT_DURATION=975ms\n'
    printf 'PLACE_CLICK_INTERVAL=100ms\n'
    printf 'PLACE_E_INTERVAL=100ms\n'
    printf 'PLACE_E_HOLD_DURATION=20ms\n'
    if test -n "$live_click"; then
      printf 'PLACE_LIVE_CLICK_INTERVAL=%s\n' "$live_click"
    fi
    if test -n "$burst_delay"; then
      printf 'PLACE_LIVE_CLICK_BURST_DELAY=%s\n' "$burst_delay"
    fi
    if test -n "$burst_margin"; then
      printf 'PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN=%s\n' "$burst_margin"
    fi
    if test -n "$live_e"; then
      printf 'PLACE_LIVE_E_INTERVAL=%s\n' "$live_e"
    fi
    printf 'POST_PLACE_WAIT=1ms\n'
  } > "$file"
}

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input allowance must not be enabled for this dry-run test\n' >&2
  exit 1
fi
printf 'PASS: live input allowance is not enabled\n'

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

points_file="$tmp_dir/points.conf"
fallback_timing_file="$tmp_dir/timing-fallback.conf"
invalid_click_timing_file="$tmp_dir/timing-invalid-click.conf"
invalid_e_timing_file="$tmp_dir/timing-invalid-e.conf"

write_points "$points_file"
write_timing "$fallback_timing_file"
write_timing "$invalid_click_timing_file" "bad"
write_timing "$invalid_e_timing_file" "1ms" "bad"

# shellcheck source=../../src/modules/place_runner.sh
. "$project_root/src/modules/place_runner.sh"
# shellcheck source=../../src/modules/place_e_runner.sh
. "$project_root/src/modules/place_e_runner.sh"

PLACE_RUNNER_POINTS_FILE="$points_file" PLACE_RUNNER_TIMING_FILE="$fallback_timing_file" place_runner_load_context
assert_equals "$(place_runner_get_timing PLACE_LIVE_CLICK_INTERVAL)" "1ms" "place live click fallback"
assert_equals "$(place_runner_get_timing PLACE_LIVE_CLICK_BURST_DELAY)" "1ms" "place live burst delay fallback"
assert_equals "$(place_runner_get_timing PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN)" "20ms" "place live burst safety margin fallback"
assert_equals "$(place_runner_duration_to_ms 1s100ms)" "1100" "place duration parser"
assert_equals "$(place_runner_live_click_interval_ms)" "1" "place live click fallback ms"
assert_equals "$(place_runner_live_click_burst_delay_ms)" "1" "place live burst delay fallback ms"
assert_equals "$(place_runner_live_click_burst_safety_margin_ms)" "20" "place live burst safety margin fallback ms"
plan_output="$(place_runner_print_live_schedule_plan forward PLACE_FORWARD_DURATION 2>&1)"
assert_contains "$plan_output" "mode=bounded-burst" "place live plan mode"
assert_contains "$plan_output" "duration_ms=1100" "place live plan duration"
assert_contains "$plan_output" "burst_count=" "place live plan burst count"
assert_contains "$plan_output" "burst_delay_ms=1" "place live plan burst delay"
assert_contains "$plan_output" "safety_margin_ms=20" "place live plan safety margin"
assert_contains "$plan_output" "point=PACK_CLICK_POINT" "place live plan target"
burst_count="$(printf '%s\n' "$plan_output" | sed -n 's/.*burst_count=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
if test -z "$burst_count" || test "$burst_count" -lt 1; then
  printf 'FAIL: place live plan burst_count was not positive: %s\n' "$plan_output" >&2
  exit 1
fi
printf 'PASS: place live plan burst_count is positive (%s)\n' "$burst_count"

PLACE_E_RUNNER_POINTS_FILE="$points_file" PLACE_E_RUNNER_TIMING_FILE="$fallback_timing_file" place_e_runner_load_context
assert_equals "$(place_e_runner_get_timing PLACE_LIVE_CLICK_INTERVAL)" "1ms" "place+E live click fallback"
assert_equals "$(place_e_runner_get_timing PLACE_LIVE_E_INTERVAL)" "25ms" "place+E live E fallback"
assert_equals "$(place_e_runner_duration_to_ms 975ms)" "975" "place+E duration parser"
assert_equals "$(place_e_runner_live_interval_ms PLACE_LIVE_E_INTERVAL)" "25" "place+E live E fallback ms"
plan_output="$(place_e_runner_print_live_schedule_plan left PLACE_LEFT_DURATION 2>&1)"
assert_contains "$plan_output" "mode=deadline" "place+E live plan mode"
assert_contains "$plan_output" "duration_ms=975" "place+E live plan duration"
assert_contains "$plan_output" "click_interval_ms=1" "place+E live plan click interval"
assert_contains "$plan_output" "e_interval_ms=25" "place+E live plan E interval"
assert_contains "$plan_output" "e_hold_ms=20" "place+E live plan E hold"
assert_contains "$plan_output" "point=PACK_CLICK_POINT" "place+E live plan target"
assert_contains "$plan_output" "click_mode=current-position" "place+E live plan click mode"

PLACE_RUNNER_POINTS_FILE="$points_file" PLACE_RUNNER_TIMING_FILE="$invalid_click_timing_file" place_runner_load_context
if output="$(place_runner_preflight 2>&1)"; then
  printf 'FAIL: invalid PLACE_LIVE_CLICK_INTERVAL passed validation\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "invalid duration: bad" "invalid live click interval"

PLACE_E_RUNNER_POINTS_FILE="$points_file" PLACE_E_RUNNER_TIMING_FILE="$invalid_e_timing_file" place_e_runner_load_context
if output="$(place_e_runner_preflight 2>&1)"; then
  printf 'FAIL: invalid PLACE_LIVE_E_INTERVAL passed validation\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "invalid duration: bad" "invalid live E interval"

printf 'PASS: live deadline scheduler dry run completed\n'
