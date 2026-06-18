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

write_valid_timing() {
  local file="$1"

  {
    printf 'BASE_PRESS_COUNT_NORMAL=0\n'
    printf 'BASE_PRESS_DELAY=5ms\n'
    printf 'POST_BASE_WAIT=5ms\n'
    printf 'PLACE_FORWARD_DURATION=1ms\n'
    printf 'PLACE_LEFT_DURATION=1ms\n'
    printf 'PLACE_CLICK_INTERVAL=1ms\n'
    printf 'PLACE_E_INTERVAL=1ms\n'
    printf 'PLACE_E_HOLD_DURATION=1ms\n'
    printf 'POST_PLACE_WAIT=1ms\n'
  } > "$file"
}

printf 'CASE: direct live invocation blocked with no gates\n'
if output="$(env -u MACRO_INPUT_MODE -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_E_RUNNER_LIVE_CONFIRM "$project_root/src/modules/place_e_runner.sh" --live 2>&1)"; then
  printf 'FAIL: direct live invocation passed with no gates\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "live place+E runner blocked" "direct no-gate live block"
assert_not_contains "$output" "TRACE place-e-runner start" "direct no-gate live block"
assert_not_contains "$output" "xdotool" "direct no-gate live block"

printf 'CASE: direct live invocation blocked with only MACRO_INPUT_MODE=live\n'
if output="$(env -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_E_RUNNER_LIVE_CONFIRM MACRO_INPUT_MODE=live "$project_root/src/modules/place_e_runner.sh" --live 2>&1)"; then
  printf 'FAIL: direct live invocation passed with only input mode gate\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "live place+E runner blocked" "direct partial-gate live block"
assert_not_contains "$output" "TRACE place-e-runner start" "direct partial-gate live block"
assert_not_contains "$output" "xdotool" "direct partial-gate live block"

printf 'CASE: macroctl live command blocked with no gates\n'
if output="$(env -u MACRO_INPUT_MODE -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_E_RUNNER_LIVE_CONFIRM "$project_root/bin/macroctl" live place-e-runner 2>&1)"; then
  printf 'FAIL: macroctl live invocation passed with no gates\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "live place+E runner blocked" "macroctl no-gate live block"
assert_not_contains "$output" "TRACE place-e-runner start" "macroctl no-gate live block"
assert_not_contains "$output" "xdotool" "macroctl no-gate live block"

printf 'CASE: dry-run still works\n'
output="$(env -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_E_RUNNER_LIVE_CONFIRM "$project_root/bin/macroctl" dry-run place-e-runner 2>&1)"
assert_contains "$output" "TRACE place-e-runner start" "dry-run still starts"
assert_contains "$output" "TRACE place-e-runner complete" "dry-run still completes"
assert_contains "$output" "xdotool keydown e" "dry-run still taps e"
assert_contains "$output" "xdotool keyup e" "dry-run still releases e"

printf 'CASE: sourced function accepts dry-run and rejects malformed mode\n'
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
points_file="$tmp_dir/points.conf"
timing_file="$tmp_dir/timing.conf"
write_valid_points "$points_file"
write_valid_timing "$timing_file"

output="$(
  env -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_E_RUNNER_LIVE_CONFIRM bash -c '
    set -euo pipefail
    project_root="$1"
    points_file="$2"
    timing_file="$3"
    . "$project_root/src/modules/place_e_runner.sh"
    PLACE_E_RUNNER_POINTS_FILE="$points_file" PLACE_E_RUNNER_TIMING_FILE="$timing_file" MACRO_INPUT_MODE=dry-run place_e_runner_run
  ' _ "$project_root" "$points_file" "$timing_file" 2>&1
)"
assert_contains "$output" "TRACE place-e-runner start" "sourced dry-run starts"
assert_contains "$output" "TRACE place-e-runner complete" "sourced dry-run completes"

if output="$(
  env -u MACRO_LIVE_INPUT_ALLOWED -u MACRO_PLACE_E_RUNNER_LIVE_CONFIRM bash -c '
    set -euo pipefail
    project_root="$1"
    points_file="$2"
    timing_file="$3"
    . "$project_root/src/modules/place_e_runner.sh"
    PLACE_E_RUNNER_POINTS_FILE="$points_file" PLACE_E_RUNNER_TIMING_FILE="$timing_file" MACRO_INPUT_MODE=invalid place_e_runner_run
  ' _ "$project_root" "$points_file" "$timing_file" 2>&1
)"; then
  printf 'FAIL: sourced invalid mode passed unexpectedly\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "unsupported MACRO_INPUT_MODE" "sourced invalid mode"
assert_not_contains "$output" "TRACE place-e-runner start" "sourced invalid mode"
assert_not_contains "$output" "xdotool" "sourced invalid mode"

printf 'PASS: place-e-runner live gate dry run completed\n'
