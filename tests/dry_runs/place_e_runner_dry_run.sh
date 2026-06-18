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

output_file="$(mktemp)"
trap 'rm -f "$output_file"' EXIT

MACRO_INPUT_MODE=dry-run "$project_root/src/modules/place_e_runner.sh" --dry-run > "$output_file" 2>&1
output="$(cat "$output_file")"

assert_contains "$output" "TRACE place-e-runner start" "runner start"
assert_contains "$output" "TRACE place-e-runner base_teleport count=1" "base teleport trace"
assert_contains "$output" "TRACE place-e-runner click point=BASE_TELEPORT_BUTTON x=398 y=33" "base point click trace"
assert_contains "$output" "TRACE place-e-runner click point=PACK_CLICK_POINT x=88 y=563" "pack point click trace"
assert_contains "$output" "TRACE place-e-runner placement_target point=PACK_CLICK_POINT x=88 y=563" "active placement target trace"
assert_contains "$output" "TRACE place-e-runner move point=PACK_CLICK_POINT x=88 y=563" "placement target move trace"
assert_contains "$output" "TRACE place-e-runner segment=forward movement_key=w duration=1s100ms" "forward segment trace"
assert_contains "$output" "TRACE place-e-runner segment=left movement_key=a duration=975ms" "left segment trace"
assert_contains "$output" "TRACE place-e-runner schedule segment=forward duration_ms=1100 click_interval_ms=100 e_interval_ms=100 e_hold_ms=20 placement_clicks=11 e_taps=11 point=PACK_CLICK_POINT click_mode=current-position" "forward combined schedule"
assert_contains "$output" "TRACE place-e-runner schedule segment=left duration_ms=975 click_interval_ms=100 e_interval_ms=100 e_hold_ms=20 placement_clicks=10 e_taps=10 point=PACK_CLICK_POINT click_mode=current-position" "left combined schedule"
assert_contains "$output" "TRACE place-e-runner schedule segment=forward click_index=1/11 point=PACK_CLICK_POINT click_mode=current-position" "forward current-position click trace"
assert_contains "$output" "TRACE input dry-run click_current button=1" "current-position input click trace"
assert_contains "$output" "xdotool keydown w" "keydown w dry-run"
assert_contains "$output" "xdotool keyup w" "keyup w dry-run"
assert_contains "$output" "xdotool keydown a" "keydown a dry-run"
assert_contains "$output" "xdotool keyup a" "keyup a dry-run"
assert_contains "$output" "xdotool keydown e" "keydown e dry-run"
assert_contains "$output" "xdotool keyup e" "keyup e dry-run"
assert_contains "$output" "TRACE place-e-runner complete" "runner complete"

potion_trace_text="TRACE potion""-runner"
place_trace_text="TRACE place""-runner"
mousemove_sync_text="mousemove ""--sync"
click_repeat_text="click ""--repeat"

assert_not_contains "$output" "$potion_trace_text" "runner output"
assert_not_contains "$output" "$place_trace_text" "runner output"
assert_not_contains "$output" "point=PLACE_HOLD_POINT" "active placement traces"
assert_not_contains "$output" "$mousemove_sync_text" "runner output"
assert_not_contains "$output" "$click_repeat_text" "runner output"

printf 'PASS: place-e-runner dry run completed\n'
