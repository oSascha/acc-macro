#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/lib/config.sh
. "$project_root/src/lib/config.sh"
# shellcheck source=../../src/lib/points.sh
. "$project_root/src/lib/points.sh"

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
points_required="$(config_project_root)/config_templates/pack_opener/points.required"
timing_required="$(config_project_root)/config_templates/pack_opener/timing.required"

config_bootstrap_pack_opener_from_templates
config_print_pack_opener_paths

points_load "$points_file"
points_print_all
points_validate_required "$points_required"

timing_load "$timing_file"
timing_validate_required "$timing_required"

assert_equal "398,33" "$(points_get BASE_TELEPORT_BUTTON)" "BASE_TELEPORT_BUTTON"
assert_equal "1100" "$(parse_duration_ms "$(timing_get PLACE_FORWARD_DURATION)")" "PLACE_FORWARD_DURATION ms"
assert_equal "975" "$(parse_duration_ms "$(timing_get PLACE_LEFT_DURATION)")" "PLACE_LEFT_DURATION ms"
assert_equal "MANUAL_FAST_NAV_BATCH_TEST" "$(timing_get POTION_PROFILE)" "POTION_PROFILE"

printf 'PASS: points-config dry run completed\n'
