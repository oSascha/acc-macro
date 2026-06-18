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

runtime_dir="$(config_pack_opener_dir)"
points_file="$runtime_dir/points.conf"
timing_file="$runtime_dir/timing.conf"
potion_plan_file="$(config_pack_opener_potion_plan_file)"
snapshot_file="$(mktemp)"

trap 'rm -f "$snapshot_file"' EXIT

config_bootstrap_pack_opener_from_templates
config_print_pack_opener_paths

cp "$potion_plan_file" "$snapshot_file"

points_load "$points_file"
timing_load "$timing_file"
potion_plan_load "$potion_plan_file"

potion_plan_validate
potion_plan_print
potion_plan_print_click_plan
potion_plan_preflight_inventory
potion_plan_project_inventory

assert_equal "40" "$(potion_plan_tier_use_amount 2_MIN)" "POTION_2_MIN_USE_AMOUNT"

decomposed="$(potion_plan_decompose_amount 40)"
assert_equal "4" "${decomposed%% *}" "POTION_2_MIN ten_x_clicks"
assert_equal "0" "${decomposed#* }" "POTION_2_MIN single_clicks"

assert_equal "360" "$(potion_plan_project_inventory 2_MIN)" "POTION_2_MIN projected inventory"
assert_equal "50" "$(parse_duration_ms "$(potion_plan_get_duration POTION_CLICK_INTERVAL)")" "POTION_CLICK_INTERVAL ms"

if ! cmp -s "$snapshot_file" "$potion_plan_file"; then
  printf 'FAIL: dry run mutated %s\n' "$potion_plan_file" >&2
  exit 1
fi

printf 'PASS: dry run did not mutate %s\n' "$potion_plan_file"
printf 'PASS: potion-plan dry run completed\n'
