#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/lib/config.sh
. "$project_root/src/lib/config.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s missing %s\n' "$label" "$needle" >&2
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
    return 1
  fi

  printf 'PASS: %s does not contain %s\n' "$label" "$needle"
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if test "$expected" != "$actual"; then
    printf 'FAIL: %s expected %s got %s\n' "$label" "$expected" "$actual" >&2
    return 1
  fi

  printf 'PASS: %s = %s\n' "$label" "$actual"
}

line_number() {
  local pattern="$1"
  local file="$2"

  grep -n -F "$pattern" "$file" | head -1 | cut -d: -f1
}

assert_line_order() {
  local first_pattern="$1"
  local second_pattern="$2"
  local label="$3"
  local first_line
  local second_line

  first_line="$(line_number "$first_pattern" "$output_file")"
  second_line="$(line_number "$second_pattern" "$output_file")"

  if test -z "$first_line" || test -z "$second_line" || test "$first_line" -ge "$second_line"; then
    printf 'FAIL: %s order mismatch\n' "$label" >&2
    printf 'first: %s line=%s\n' "$first_pattern" "${first_line:-missing}" >&2
    printf 'second: %s line=%s\n' "$second_pattern" "${second_line:-missing}" >&2
    return 1
  fi

  printf 'PASS: %s order\n' "$label"
}

snapshot_file="$(mktemp)"
output_file="$(mktemp)"
trap 'rm -f "$snapshot_file" "$output_file"' EXIT

config_bootstrap_pack_opener_from_templates >/dev/null
potion_plan_file="$(config_pack_opener_potion_plan_file)"
cp "$potion_plan_file" "$snapshot_file"

MACRO_INPUT_MODE=dry-run "$project_root/src/modules/potion_runner.sh" --dry-run > "$output_file" 2>&1
output="$(cat "$output_file")"

assert_contains "$output" "TRACE potion-runner start" "runner start"
assert_contains "$output" "TRACE potion-runner tier=2_MIN amount=40 ten_x_clicks=4 single_clicks=0" "2-minute tier trace"
assert_contains "$output" "TRACE potion-runner pre_menu_wait key=POTION_PRE_MENU_CLICK_WAIT duration=1ms" "pre-menu wait trace"
assert_contains "$output" "TRACE potion-runner click point=MENU_BUTTON x=32 y=356" "menu click trace"
assert_contains "$output" "TRACE potion-runner post_inventory_open_wait key=POST_INVENTORY_OPEN_WAIT duration=" "post inventory wait trace"
assert_contains "$output" "TRACE potion-runner tier=2_MIN ten_x_button=POTION_2_MIN_USE_10X_BUTTON" "2-minute calibrated 10x button"
assert_not_contains "$output" "ten_x_button_fallback=USE_10X_BUTTON" "2-minute 10x fallback"
assert_contains "$output" "TRACE potion-runner projected_inventory tier=2_MIN before=400 used=40 after=360" "projected inventory trace"
assert_contains "$output" "TRACE potion-runner complete" "runner complete"
assert_line_order "TRACE potion-runner pre_menu_wait key=POTION_PRE_MENU_CLICK_WAIT" "TRACE potion-runner click point=MENU_BUTTON" "pre-menu wait before menu click"
assert_line_order "TRACE potion-runner click point=MENU_BUTTON" "TRACE potion-runner post_inventory_open_wait key=POST_INVENTORY_OPEN_WAIT" "post inventory wait after menu click"
assert_line_order "TRACE potion-runner post_inventory_open_wait key=POST_INVENTORY_OPEN_WAIT" "TRACE potion-runner click point=POTION_2_MIN" "post inventory wait before potion tier click"

ten_x_count="$(grep -c "TRACE potion-runner tier=2_MIN click_type=10x click_index=.* point=POTION_2_MIN_USE_10X_BUTTON" "$output_file" || true)"
assert_equal "4" "$ten_x_count" "2-minute 10x click trace count"

ten_x_point_clicks="$(grep -c "TRACE potion-runner click point=POTION_2_MIN_USE_10X_BUTTON x=468 y=383" "$output_file" || true)"
assert_equal "4" "$ten_x_point_clicks" "resolved 10x point click count"

mousemove_sync_text="mousemove ""--sync"
click_repeat_text="click ""--repeat"
assert_not_contains "$output" "$mousemove_sync_text" "runner output"
assert_not_contains "$output" "$click_repeat_text" "runner output"

if ! cmp -s "$snapshot_file" "$potion_plan_file"; then
  printf 'FAIL: potion runner dry run mutated %s\n' "$potion_plan_file" >&2
  exit 1
fi

printf 'PASS: potion runner dry run did not mutate %s\n' "$potion_plan_file"
printf 'PASS: potion-runner dry run completed\n'
