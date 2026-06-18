#!/usr/bin/env bash

pack_opener_runner_script="${BASH_SOURCE[0]}"
pack_opener_runner_dir="${pack_opener_runner_script%/*}"
if test "$pack_opener_runner_dir" = "$pack_opener_runner_script"; then
  pack_opener_runner_dir="."
fi

pack_opener_runner_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$pack_opener_runner_project_root"; then
  pack_opener_runner_project_root="$(cd "$pack_opener_runner_dir/../.." && pwd -P)"
fi

PACK_OPENER_MAX_DRY_RUN_CYCLES="${PACK_OPENER_MAX_DRY_RUN_CYCLES:-3}"
PACK_OPENER_DEFAULT_DRY_RUN_CYCLES=2

# shellcheck source=../lib/config.sh
. "$pack_opener_runner_project_root/src/lib/config.sh"
# shellcheck source=../lib/points.sh
. "$pack_opener_runner_project_root/src/lib/points.sh"
# shellcheck source=../lib/potion_plan.sh
. "$pack_opener_runner_project_root/src/lib/potion_plan.sh"
# shellcheck source=../lib/input.sh
. "$pack_opener_runner_project_root/src/lib/input.sh"

pack_opener_runner_trace() {
  printf 'TRACE pack-opener-runner %s\n' "$*"
}

pack_opener_runner_load_context() {
  local runtime_dir
  local points_file="${PACK_OPENER_RUNNER_POINTS_FILE:-}"
  local timing_file="${PACK_OPENER_RUNNER_TIMING_FILE:-}"
  local potion_plan_file="${PACK_OPENER_RUNNER_POTION_PLAN_FILE:-}"

  if test -z "$points_file" || test -z "$timing_file" || test -z "$potion_plan_file"; then
    runtime_dir="$(config_pack_opener_dir)"
    config_bootstrap_pack_opener_from_templates
    points_file="${points_file:-$runtime_dir/points.conf}"
    timing_file="${timing_file:-$runtime_dir/timing.conf}"
    potion_plan_file="${potion_plan_file:-$(config_pack_opener_potion_plan_file)}"
  fi

  export PLACE_RUNNER_POINTS_FILE="${PLACE_RUNNER_POINTS_FILE:-$points_file}"
  export PLACE_RUNNER_TIMING_FILE="${PLACE_RUNNER_TIMING_FILE:-$timing_file}"
  export PLACE_E_RUNNER_POINTS_FILE="${PLACE_E_RUNNER_POINTS_FILE:-$points_file}"
  export PLACE_E_RUNNER_TIMING_FILE="${PLACE_E_RUNNER_TIMING_FILE:-$timing_file}"
  export POTION_RUNNER_POINTS_FILE="${POTION_RUNNER_POINTS_FILE:-$points_file}"
  export POTION_RUNNER_TIMING_FILE="${POTION_RUNNER_TIMING_FILE:-$timing_file}"
  export POTION_RUNNER_POTION_PLAN_FILE="${POTION_RUNNER_POTION_PLAN_FILE:-$potion_plan_file}"

  points_load "$points_file"
  timing_load "$timing_file"
  potion_plan_load "$potion_plan_file"
}

pack_opener_runner_parse_cycles() {
  local value="${1:-$PACK_OPENER_DEFAULT_DRY_RUN_CYCLES}"

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: cycles must be a positive integer: %s\n' "$value" >&2
    return 2
  fi

  if test "$value" -lt 1; then
    printf 'ERROR: cycles must be at least 1: %s\n' "$value" >&2
    return 2
  fi

  if ! [[ "$PACK_OPENER_MAX_DRY_RUN_CYCLES" =~ ^[0-9]+$ ]] ||
    test "$PACK_OPENER_MAX_DRY_RUN_CYCLES" -lt 1; then
    printf 'ERROR: PACK_OPENER_MAX_DRY_RUN_CYCLES must be a positive integer: %s\n' "$PACK_OPENER_MAX_DRY_RUN_CYCLES" >&2
    return 2
  fi

  if test "$value" -gt "$PACK_OPENER_MAX_DRY_RUN_CYCLES"; then
    printf 'ERROR: cycles %s exceeds max %s\n' "$value" "$PACK_OPENER_MAX_DRY_RUN_CYCLES" >&2
    return 2
  fi

  printf '%s\n' "$value"
}

pack_opener_runner_validate_return_base_points() {
  local failures=0

  if points_get BASE_TELEPORT_BUTTON >/dev/null; then
    printf 'OK: pack opener return-to-base point BASE_TELEPORT_BUTTON = %s\n' "$(points_get BASE_TELEPORT_BUTTON)"
  else
    failures=$((failures + 1))
  fi

  test "$failures" -eq 0
}

pack_opener_runner_validate_return_base_timing() {
  local failures=0
  local value
  local ms

  if value="$(timing_get BASE_PRESS_COUNT_NORMAL)"; then
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      printf 'OK: pack opener return-to-base timing BASE_PRESS_COUNT_NORMAL = %s\n' "$value"
    else
      printf 'ERROR: pack opener return-to-base timing BASE_PRESS_COUNT_NORMAL must be a non-negative integer: %s\n' "$value" >&2
      failures=$((failures + 1))
    fi
  else
    failures=$((failures + 1))
  fi

  if value="$(timing_get BASE_PRESS_DELAY)"; then
    if ms="$(parse_duration_ms "$value")"; then
      printf 'OK: pack opener return-to-base timing BASE_PRESS_DELAY = %s (%sms)\n' "$value" "$ms"
    else
      printf 'ERROR: pack opener return-to-base timing BASE_PRESS_DELAY invalid: %s\n' "$value" >&2
      failures=$((failures + 1))
    fi
  else
    failures=$((failures + 1))
  fi

  if value="$(timing_get POST_SECOND_BASE_WAIT)"; then
    if ms="$(parse_duration_ms "$value")"; then
      printf 'OK: pack opener return-to-base timing POST_SECOND_BASE_WAIT = %s (%sms)\n' "$value" "$ms"
    else
      printf 'ERROR: pack opener return-to-base timing POST_SECOND_BASE_WAIT invalid: %s\n' "$value" >&2
      failures=$((failures + 1))
    fi
  else
    failures=$((failures + 1))
  fi

  test "$failures" -eq 0
}

pack_opener_runner_resolve_point() {
  local name="${1:-}"

  if test -z "$name"; then
    printf 'ERROR: pack_opener_runner_resolve_point requires a point name\n' >&2
    return 2
  fi

  points_get "$name"
}

pack_opener_runner_click_named_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(pack_opener_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  pack_opener_runner_trace "click point=${name} x=${x} y=${y}"
  click_point "$x" "$y"
}

pack_opener_runner_return_to_base() {
  local cycle="$1"
  local base_count
  local i

  base_count="$(timing_get BASE_PRESS_COUNT_NORMAL)" || return 2
  pack_opener_runner_trace "cycle=${cycle} return_to_base count=${base_count}"

  for ((i = 1; i <= base_count; i++)); do
    pack_opener_runner_trace "cycle=${cycle} return_to_base click_index=${i}/${base_count} point=BASE_TELEPORT_BUTTON"
    pack_opener_runner_click_named_point BASE_TELEPORT_BUTTON || return 2
    input_sleep "$(timing_get BASE_PRESS_DELAY)" || return 2
  done

  input_sleep "$(timing_get POST_SECOND_BASE_WAIT)" || return 2
}

pack_opener_runner_preflight() {
  local failures=0

  pack_opener_runner_validate_return_base_points || failures=$((failures + 1))
  pack_opener_runner_validate_return_base_timing || failures=$((failures + 1))

  test "$failures" -eq 0
}

pack_opener_runner_load_child_runners() {
  # shellcheck source=place_runner.sh
  . "$pack_opener_runner_project_root/src/modules/place_runner.sh"
  # shellcheck source=place_e_runner.sh
  . "$pack_opener_runner_project_root/src/modules/place_e_runner.sh"
  # shellcheck source=potion_runner.sh
  . "$pack_opener_runner_project_root/src/modules/potion_runner.sh"
}

pack_opener_runner_run_cycle() {
  local cycle="$1"
  local kind="main"

  if test "$cycle" -eq 1; then
    kind="first"
  fi

  pack_opener_runner_trace "cycle=${cycle} kind=${kind} begin"

  if test "$cycle" -eq 1; then
    pack_opener_runner_trace "cycle=${cycle} phase=place_only runner=place_runner"
    place_runner_run || return 2
  else
    pack_opener_runner_trace "cycle=${cycle} phase=place_e runner=place_e_runner"
    place_e_runner_run || return 2
  fi

  pack_opener_runner_trace "cycle=${cycle} phase=return_to_base"
  pack_opener_runner_return_to_base "$cycle" || return 2

  pack_opener_runner_trace "cycle=${cycle} phase=potion runner=potion_runner"
  potion_runner_run || return 2

  pack_opener_runner_trace "cycle=${cycle} complete"
}

pack_opener_runner_run() {
  local cycles="${1:-$PACK_OPENER_DEFAULT_DRY_RUN_CYCLES}"
  local mode
  local cycle

  mode="$(input_mode)" || return 2
  if test "$mode" != "dry-run"; then
    printf 'ERROR: Pack Opener runner only supports MACRO_INPUT_MODE=dry-run in contract 07A\n' >&2
    return 2
  fi

  cycles="$(pack_opener_runner_parse_cycles "$cycles")" || return 2
  pack_opener_runner_load_context || return $?
  pack_opener_runner_preflight || return $?
  pack_opener_runner_load_child_runners

  pack_opener_runner_trace "start cycles=${cycles}"

  for ((cycle = 1; cycle <= cycles; cycle++)); do
    pack_opener_runner_run_cycle "$cycle" || return 2
  done

  pack_opener_runner_trace "complete cycles=${cycles}"
}

pack_opener_runner_usage() {
  printf 'Usage: %s --dry-run [--cycles N]\n' "$0" >&2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail

  cycles="$PACK_OPENER_DEFAULT_DRY_RUN_CYCLES"

  case "${1:---dry-run}" in
    --dry-run)
      shift || true
      ;;
    --live)
      printf 'ERROR: live Pack Opener runner is unavailable in contract 07A\n' >&2
      exit 2
      ;;
    *)
      pack_opener_runner_usage
      exit 2
      ;;
  esac

  while test "$#" -gt 0; do
    case "$1" in
      --cycles)
        shift
        if test "$#" -eq 0; then
          printf 'ERROR: --cycles requires a value\n' >&2
          exit 2
        fi
        cycles="$1"
        shift
        ;;
      --live)
        printf 'ERROR: live Pack Opener runner is unavailable in contract 07A\n' >&2
        exit 2
        ;;
      *)
        pack_opener_runner_usage
        exit 2
        ;;
    esac
  done

  export MACRO_INPUT_MODE=dry-run
  pack_opener_runner_run "$cycles"
fi
