#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/modules/potion_runner.sh
. "$project_root/src/modules/potion_runner.sh"

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

write_plan() {
  local file="$1"
  local plan_enabled="$2"
  local p2_enabled="$3"
  local p2_amount="$4"
  local p2_inventory="$5"

  {
    printf 'POTION_PLAN_ENABLED=%s\n\n' "$plan_enabled"
    printf 'POTION_2_MIN_ENABLED=%s\n' "$p2_enabled"
    printf 'POTION_2_MIN_USE_AMOUNT=%s\n' "$p2_amount"
    printf 'POTION_2_MIN_INVENTORY=%s\n\n' "$p2_inventory"
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

write_potion_only_points() {
  local file="$1"

  {
    printf 'MENU_BUTTON_X=32\n'
    printf 'MENU_BUTTON_Y=356\n'
    printf 'POTION_2_MIN_X=427\n'
    printf 'POTION_2_MIN_Y=258\n'
    printf 'POTION_2_MIN_USE_SINGLE_BUTTON_X=\n'
    printf 'POTION_2_MIN_USE_SINGLE_BUTTON_Y=\n'
    printf 'POTION_2_MIN_USE_10X_BUTTON_X=\n'
    printf 'POTION_2_MIN_USE_10X_BUTTON_Y=\n'
    printf 'USE_10X_BUTTON_X=464\n'
    printf 'USE_10X_BUTTON_Y=379\n'
    printf 'CLOSE_BUTTON_X=622\n'
    printf 'CLOSE_BUTTON_Y=183\n'
  } > "$file"
}

write_missing_menu_points() {
  local file="$1"

  write_potion_only_points "$file"
  {
    printf 'MENU_BUTTON_X=\n'
    printf 'MENU_BUTTON_Y=\n'
  } >> "$file"
}

write_missing_potion_points() {
  local file="$1"

  {
    printf 'MENU_BUTTON_X=\n'
    printf 'MENU_BUTTON_Y=\n'
    printf 'POTION_2_MIN_X=\n'
    printf 'POTION_2_MIN_Y=\n'
    printf 'POTION_2_MIN_USE_10X_BUTTON_X=\n'
    printf 'POTION_2_MIN_USE_10X_BUTTON_Y=\n'
    printf 'USE_10X_BUTTON_X=\n'
    printf 'USE_10X_BUTTON_Y=\n'
    printf 'CLOSE_BUTTON_X=\n'
    printf 'CLOSE_BUTTON_Y=\n'
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

expect_preflight_passes() {
  local label="$1"

  if ! potion_runner_preflight >/dev/null; then
    printf 'FAIL: %s preflight failed\n' "$label" >&2
    return 1
  fi

  printf 'PASS: %s preflight passed\n' "$label"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

timing_file="$tmp_dir/timing.conf"
plan_file="$tmp_dir/potion_plan.conf"
points_file="$tmp_dir/points.conf"

cp "$project_root/config_templates/pack_opener/timing.conf" "$timing_file"

printf 'CASE: potion runner does not require pack placement points\n'
write_potion_only_points "$points_file"
write_plan "$plan_file" 1 1 40 400
load_temp_context "$points_file" "$timing_file" "$plan_file"
expect_preflight_passes "potion-only points without pack points"

printf 'CASE: missing menu point fails when plan has work\n'
write_missing_menu_points "$points_file"
write_plan "$plan_file" 1 1 40 400
load_temp_context "$points_file" "$timing_file" "$plan_file"
if output="$(potion_runner_preflight 2>&1)"; then
  printf 'FAIL: preflight passed with missing active menu point\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "MENU_BUTTON" "missing active menu failure"

printf 'CASE: disabled plan does not require potion, menu, or close points\n'
write_missing_potion_points "$points_file"
write_plan "$plan_file" 0 1 40 400
load_temp_context "$points_file" "$timing_file" "$plan_file"
expect_preflight_passes "disabled plan with missing potion points"

POTION_RUNNER_POINTS_FILE="$points_file"
POTION_RUNNER_TIMING_FILE="$timing_file"
POTION_RUNNER_POTION_PLAN_FILE="$plan_file"
MACRO_INPUT_MODE=dry-run
output="$(potion_runner_run 2>&1)"
assert_contains "$output" "TRACE potion-runner skipped enabled=0" "disabled plan runner path"

printf 'PASS: potion-runner negative dry run completed\n'
