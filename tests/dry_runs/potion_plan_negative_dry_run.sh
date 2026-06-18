#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/lib/config.sh
. "$project_root/src/lib/config.sh"
# shellcheck source=../../src/lib/points.sh
. "$project_root/src/lib/points.sh"
# shellcheck source=../../src/lib/potion_plan.sh
. "$project_root/src/lib/potion_plan.sh"

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

assert_decomposition() {
  local amount="$1"
  local expected_ten_x="$2"
  local expected_single="$3"
  local decomposed

  decomposed="$(potion_plan_decompose_amount "$amount")"
  assert_equal "$expected_ten_x" "${decomposed%% *}" "$amount ten_x_clicks"
  assert_equal "$expected_single" "${decomposed#* }" "$amount single_clicks"
}

write_plan() {
  local file="$1"
  local plan_enabled="$2"
  local p2_enabled="$3"
  local p2_amount="$4"
  local p2_inventory="$5"
  local p6_enabled="$6"
  local p6_amount="$7"
  local p6_inventory="$8"
  local p15_enabled="$9"
  local p15_amount="${10}"
  local p15_inventory="${11}"

  {
    printf 'POTION_PLAN_ENABLED=%s\n\n' "$plan_enabled"
    printf 'POTION_2_MIN_ENABLED=%s\n' "$p2_enabled"
    printf 'POTION_2_MIN_USE_AMOUNT=%s\n' "$p2_amount"
    printf 'POTION_2_MIN_INVENTORY=%s\n\n' "$p2_inventory"
    printf 'POTION_6_MIN_ENABLED=%s\n' "$p6_enabled"
    printf 'POTION_6_MIN_USE_AMOUNT=%s\n' "$p6_amount"
    printf 'POTION_6_MIN_INVENTORY=%s\n\n' "$p6_inventory"
    printf 'POTION_15_MIN_ENABLED=%s\n' "$p15_enabled"
    printf 'POTION_15_MIN_USE_AMOUNT=%s\n' "$p15_amount"
    printf 'POTION_15_MIN_INVENTORY=%s\n\n' "$p15_inventory"
    printf 'POTION_NAV_CLICK_INTERVAL=30ms\n'
    printf 'POTION_CLICK_INTERVAL=50ms\n\n'
    printf 'CLOSE_INVENTORY=1\n'
  } > "$file"
}

write_points_missing_active() {
  local file="$1"

  {
    printf 'MENU_BUTTON_X=\n'
    printf 'MENU_BUTTON_Y=\n'
    printf 'POTION_2_MIN_X=\n'
    printf 'POTION_2_MIN_Y=\n'
    printf 'POTION_2_MIN_USE_SINGLE_BUTTON_X=\n'
    printf 'POTION_2_MIN_USE_SINGLE_BUTTON_Y=\n'
    printf 'POTION_2_MIN_USE_10X_BUTTON_X=\n'
    printf 'POTION_2_MIN_USE_10X_BUTTON_Y=\n'
    printf 'USE_10X_BUTTON_X=\n'
    printf 'USE_10X_BUTTON_Y=\n'
    printf 'CLOSE_BUTTON_X=\n'
    printf 'CLOSE_BUTTON_Y=\n'
  } > "$file"
}

expect_validate_passes() {
  local label="$1"

  if ! potion_plan_validate >/dev/null; then
    printf 'FAIL: %s validation failed\n' "$label" >&2
    return 1
  fi

  printf 'PASS: %s validation passed\n' "$label"
}

expect_inventory_passes() {
  local label="$1"
  local output

  if ! output="$(potion_plan_preflight_inventory 2>&1)"; then
    printf 'FAIL: %s inventory preflight failed\n' "$label" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  printf 'PASS: %s inventory preflight passed\n' "$label"
  printf '%s\n' "$output"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

normal_points="$project_root/config_templates/pack_opener/points.conf"
plan_file="$tmp_dir/potion_plan.conf"
missing_points_file="$tmp_dir/points_missing_active.conf"

assert_decomposition 43 4 3
assert_decomposition 7 0 7
assert_decomposition 50 5 0

printf 'CASE: 2-minute singles required but single button unset\n'
write_plan "$plan_file" 1 1 43 400 0 0 0 0 0 0
points_load "$normal_points"
potion_plan_load "$plan_file"
expect_validate_passes "2-minute singles required"
expect_inventory_passes "2-minute singles required" >/dev/null
if output="$(potion_plan_print_click_plan 2>&1)"; then
  printf 'FAIL: click plan passed with missing 2-minute single button\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "POTION_2_MIN_USE_SINGLE_BUTTON" "missing single button failure"
assert_not_contains "$output" "TIER 2_MIN" "missing single button failed before click plan"

printf 'CASE: inventory block before click plan\n'
write_plan "$plan_file" 1 1 40 30 0 0 0 0 0 0
points_load "$normal_points"
potion_plan_load "$plan_file"
expect_validate_passes "inventory block"
if output="$(potion_plan_preflight_inventory 2>&1)"; then
  printf 'FAIL: inventory preflight passed with insufficient inventory\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "FAIL: inventory tier=2_MIN" "inventory block preflight"
if output="$(potion_plan_print_click_plan 2>&1)"; then
  printf 'FAIL: click plan passed with insufficient inventory\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "FAIL: inventory tier=2_MIN" "inventory block click plan"
assert_not_contains "$output" "TIER 2_MIN" "inventory block failed before click plan"

printf 'CASE: disabled tiers with zero inventory are skipped\n'
write_plan "$plan_file" 1 1 40 400 0 99 0 0 99 0
points_load "$normal_points"
potion_plan_load "$plan_file"
expect_validate_passes "disabled tier overdraw"
output="$(expect_inventory_passes "disabled tier overdraw")"
assert_contains "$output" "tier=6_MIN enabled=0 amount=99 inventory=0 skipped" "disabled 6-minute skip"
assert_contains "$output" "tier=15_MIN enabled=0 amount=99 inventory=0 skipped" "disabled 15-minute skip"

printf 'CASE: disabled plan does not require menu, close, or tier points\n'
write_plan "$plan_file" 0 1 40 400 0 0 0 0 0 0
write_points_missing_active "$missing_points_file"
points_load "$missing_points_file"
potion_plan_load "$plan_file"
expect_validate_passes "disabled plan"
output="$(expect_inventory_passes "disabled plan")"
assert_contains "$output" "potion_plan_enabled=0 skipped" "disabled plan inventory skip"
if ! output="$(potion_plan_print_click_plan 2>&1)"; then
  printf 'FAIL: disabled plan click plan failed\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
assert_contains "$output" "TRACE potion-plan skipped enabled=0" "disabled plan click plan skip"

printf 'PASS: potion-plan negative dry run completed\n'
