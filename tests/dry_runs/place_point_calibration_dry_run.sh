#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../../src/lib/config.sh
. "$project_root/src/lib/config.sh"
# shellcheck source=../../src/lib/points.sh
. "$project_root/src/lib/points.sh"

print_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(points_get "$name")" || return 2
  x="${point%,*}"
  y="${point#*,}"
  printf 'POINT %s x=%s y=%s\n' "$name" "$x" "$y"
}

config_bootstrap_pack_opener_from_templates
points_load "$(config_pack_opener_dir)/points.conf"

base_point="$(points_get BASE_TELEPORT_BUTTON)"
pack_point="$(points_get PACK_CLICK_POINT)"
place_point="$(points_get PLACE_HOLD_POINT)"

print_point BASE_TELEPORT_BUTTON
print_point PACK_CLICK_POINT
print_point PLACE_HOLD_POINT

if test "$pack_point" != "88,563"; then
  printf 'ERROR: PACK_CLICK_POINT expected x=88 y=563, got %s\n' "$pack_point" >&2
  exit 1
fi

if test "$pack_point" = "435,391"; then
  printf 'ERROR: PACK_CLICK_POINT still has old incorrect value x=435 y=391\n' >&2
  exit 1
fi

if test "$place_point" != "88,563"; then
  printf 'ERROR: PLACE_HOLD_POINT expected x=88 y=563, got %s\n' "$place_point" >&2
  exit 1
fi

if test "$base_point" != "398,33"; then
  printf 'ERROR: BASE_TELEPORT_BUTTON expected x=398 y=33, got %s\n' "$base_point" >&2
  exit 1
fi

printf 'OK: active placement target is PACK_CLICK_POINT x=88 y=563\n'
printf 'NOTE: PLACE_HOLD_POINT is legacy compatibility only\n'
printf 'PASS: place point calibration dry run completed\n'
