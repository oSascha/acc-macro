#!/usr/bin/env bash

place_runner_script="${BASH_SOURCE[0]}"
place_runner_dir="${place_runner_script%/*}"
if test "$place_runner_dir" = "$place_runner_script"; then
  place_runner_dir="."
fi

place_runner_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$place_runner_project_root"; then
  place_runner_project_root="$(cd "$place_runner_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$place_runner_project_root/src/lib/config.sh"
# shellcheck source=../lib/points.sh
. "$place_runner_project_root/src/lib/points.sh"
# shellcheck source=../lib/input.sh
. "$place_runner_project_root/src/lib/input.sh"

place_runner_trace() {
  printf 'TRACE place-runner %s\n' "$*"
}

place_runner_load_context() {
  local runtime_dir
  local points_file="${PLACE_RUNNER_POINTS_FILE:-}"
  local timing_file="${PLACE_RUNNER_TIMING_FILE:-}"

  if test -z "$points_file" || test -z "$timing_file"; then
    runtime_dir="$(config_pack_opener_dir)"
    config_bootstrap_pack_opener_from_templates
    points_file="${points_file:-$runtime_dir/points.conf}"
    timing_file="${timing_file:-$runtime_dir/timing.conf}"
  fi

  points_load "$points_file"
  timing_load "$timing_file"
}

place_runner_get_timing() {
  local key="${1:-}"
  local value

  if test -z "$key"; then
    printf 'ERROR: place_runner_get_timing requires a timing key\n' >&2
    return 2
  fi

  if value="$(timing_get "$key" 2>/dev/null)"; then
    printf '%s\n' "$value"
    return 0
  fi

  case "$key" in
    PLACE_CLICK_INTERVAL)
      printf '100ms\n'
      return 0
      ;;
    PLACE_LIVE_CLICK_INTERVAL)
      printf '1ms\n'
      return 0
      ;;
    PLACE_LIVE_CLICK_BURST_DELAY)
      printf '8ms\n'
      return 0
      ;;
    PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN)
      printf '20ms\n'
      return 0
      ;;
  esac

  timing_get "$key"
}

place_runner_validate_required_points() {
  local point
  local failures=0

  for point in BASE_TELEPORT_BUTTON PACK_CLICK_POINT; do
    if points_get "$point" >/dev/null; then
      printf 'OK: place runner point %s = %s\n' "$point" "$(points_get "$point")"
    else
      failures=$((failures + 1))
    fi
  done

  test "$failures" -eq 0
}

place_runner_validate_count_timing() {
  local key="$1"
  local value

  value="$(place_runner_get_timing "$key")" || return 2
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: place runner timing %s must be a non-negative integer: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf 'OK: place runner timing %s = %s\n' "$key" "$value"
}

place_runner_validate_duration_timing() {
  local key="$1"
  local require_positive="${2:-0}"
  local value
  local ms

  value="$(place_runner_get_timing "$key")" || return 2
  ms="$(parse_duration_ms "$value")" || return 2

  if test "$require_positive" = "1" && test "$ms" -le 0; then
    printf 'ERROR: place runner timing %s must be greater than 0: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf 'OK: place runner timing %s = %s (%sms)\n' "$key" "$value" "$ms"
}

place_runner_validate_required_timing() {
  local failures=0

  place_runner_validate_count_timing BASE_PRESS_COUNT_NORMAL || failures=$((failures + 1))
  place_runner_validate_duration_timing BASE_PRESS_DELAY 0 || failures=$((failures + 1))
  place_runner_validate_duration_timing POST_BASE_WAIT 0 || failures=$((failures + 1))
  place_runner_validate_duration_timing PLACE_FORWARD_DURATION 1 || failures=$((failures + 1))
  place_runner_validate_duration_timing PLACE_LEFT_DURATION 1 || failures=$((failures + 1))
  place_runner_validate_duration_timing POST_PLACE_WAIT 0 || failures=$((failures + 1))
  place_runner_validate_duration_timing PLACE_CLICK_INTERVAL 1 || failures=$((failures + 1))
  place_runner_validate_duration_timing PLACE_LIVE_CLICK_INTERVAL 1 || failures=$((failures + 1))
  place_runner_validate_duration_timing PLACE_LIVE_CLICK_BURST_DELAY 0 || failures=$((failures + 1))
  place_runner_validate_duration_timing PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN 0 || failures=$((failures + 1))

  test "$failures" -eq 0
}

place_runner_resolve_point() {
  local name="${1:-}"

  if test -z "$name"; then
    printf 'ERROR: place_runner_resolve_point requires a point name\n' >&2
    return 2
  fi

  points_get "$name"
}

place_runner_click_named_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(place_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  place_runner_trace "click point=${name} x=${x} y=${y}"
  click_point "$x" "$y"
}

place_runner_move_named_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(place_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  place_runner_trace "move point=${name} x=${x} y=${y}"
  move_mouse "$x" "$y"
}

place_runner_trace_named_point() {
  local event="$1"
  local name="$2"
  local point
  local x
  local y

  point="$(place_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  place_runner_trace "${event} point=${name} x=${x} y=${y}"
}

place_runner_move_to_placement_target() {
  place_runner_trace_named_point placement_target PACK_CLICK_POINT || return $?
  place_runner_move_named_point PACK_CLICK_POINT
}

place_runner_calculate_click_count() {
  local duration_ms="${1:-}"
  local interval_ms="${2:-}"

  if ! [[ "$duration_ms" =~ ^[0-9]+$ ]] || ! [[ "$interval_ms" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: click count inputs must be non-negative integers\n' >&2
    return 2
  fi

  if test "$interval_ms" -le 0; then
    printf 'ERROR: click interval must be greater than 0\n' >&2
    return 2
  fi

  printf '%s\n' "$(((duration_ms + interval_ms - 1) / interval_ms))"
}

place_runner_current_time_ms() {
  date +%s%3N
}

place_runner_duration_to_ms() {
  parse_duration_ms "${1:-}"
}

place_runner_live_click_interval_ms() {
  local interval
  local interval_ms

  interval="$(place_runner_get_timing PLACE_LIVE_CLICK_INTERVAL)" || return 2
  interval_ms="$(place_runner_duration_to_ms "$interval")" || return 2

  if test "$interval_ms" -le 0; then
    printf 'ERROR: PLACE_LIVE_CLICK_INTERVAL must be greater than 0: %s\n' "$interval" >&2
    return 2
  fi

  printf '%s\n' "$interval_ms"
}

place_runner_live_click_burst_delay_ms() {
  local delay
  local delay_ms

  delay="$(place_runner_get_timing PLACE_LIVE_CLICK_BURST_DELAY)" || return 2
  delay_ms="$(place_runner_duration_to_ms "$delay")" || return 2

  if test "$delay_ms" -gt "$INPUT_CLICK_BURST_MAX_DELAY_MS"; then
    printf 'ERROR: PLACE_LIVE_CLICK_BURST_DELAY exceeds max %sms: %s\n' "$INPUT_CLICK_BURST_MAX_DELAY_MS" "$delay" >&2
    return 2
  fi

  printf '%s\n' "$delay_ms"
}

place_runner_live_click_burst_safety_margin_ms() {
  local margin

  margin="$(place_runner_get_timing PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN)" || return 2
  place_runner_duration_to_ms "$margin"
}

place_runner_calculate_live_burst_count() {
  local duration_ms="${1:-}"
  local delay_ms="${2:-}"
  local safety_margin_ms="${3:-}"
  local usable_ms
  local count

  if ! [[ "$duration_ms" =~ ^[0-9]+$ ]] ||
    ! [[ "$delay_ms" =~ ^[0-9]+$ ]] ||
    ! [[ "$safety_margin_ms" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: live burst inputs must be non-negative integers\n' >&2
    return 2
  fi

  usable_ms=$((duration_ms - safety_margin_ms))
  if test "$usable_ms" -lt 1; then
    printf 'ERROR: live burst usable duration must be at least 1ms: duration_ms=%s safety_margin_ms=%s\n' "$duration_ms" "$safety_margin_ms" >&2
    return 2
  fi

  if test "$delay_ms" -eq 0; then
    count="$usable_ms"
  else
    count=$((usable_ms / delay_ms))
  fi

  if test "$count" -lt 1; then
    count=1
  fi

  if test "$count" -gt "$INPUT_CLICK_BURST_MAX_COUNT"; then
    count="$INPUT_CLICK_BURST_MAX_COUNT"
  fi

  printf '%s\n' "$count"
}

place_runner_live_burst_plan() {
  local duration_key="$1"
  local duration
  local duration_ms
  local delay_ms
  local safety_margin_ms
  local burst_count

  duration="$(place_runner_get_timing "$duration_key")" || return 2
  duration_ms="$(place_runner_duration_to_ms "$duration")" || return 2
  delay_ms="$(place_runner_live_click_burst_delay_ms)" || return 2
  safety_margin_ms="$(place_runner_live_click_burst_safety_margin_ms)" || return 2
  burst_count="$(place_runner_calculate_live_burst_count "$duration_ms" "$delay_ms" "$safety_margin_ms")" || return 2

  printf '%s %s %s %s\n' "$duration_ms" "$burst_count" "$delay_ms" "$safety_margin_ms"
}

place_runner_live_sleep_until() {
  local deadline_ms="$1"
  local next_event_ms="$2"
  local now_ms
  local target_ms
  local sleep_ms

  now_ms="$(place_runner_current_time_ms)" || return 2
  if test "$now_ms" -ge "$deadline_ms"; then
    return 0
  fi

  target_ms="$deadline_ms"
  if test "$next_event_ms" -lt "$target_ms"; then
    target_ms="$next_event_ms"
  fi

  sleep_ms=$((target_ms - now_ms))
  if test "$sleep_ms" -gt 0; then
    sleep_duration "${sleep_ms}ms" || return 2
  fi
}

place_runner_print_live_schedule_plan() {
  local segment="$1"
  local duration_key="$2"
  local duration_ms
  local burst_count
  local delay_ms
  local safety_margin_ms
  local plan

  plan="$(place_runner_live_burst_plan "$duration_key")" || return 2
  read -r duration_ms burst_count delay_ms safety_margin_ms <<< "$plan"

  place_runner_trace "live_burst_schedule segment=${segment} mode=bounded-burst duration_ms=${duration_ms} burst_count=${burst_count} burst_delay_ms=${delay_ms} safety_margin_ms=${safety_margin_ms} point=PACK_CLICK_POINT"
}

place_runner_run_live_click_burst() {
  local segment="$1"
  local duration_key="$2"
  local duration_ms
  local burst_count
  local delay_ms
  local safety_margin_ms
  local plan
  local start_ms
  local deadline_ms
  local now_ms
  local remaining_ms
  local overrun_ms

  plan="$(place_runner_live_burst_plan "$duration_key")" || return 2
  read -r duration_ms burst_count delay_ms safety_margin_ms <<< "$plan"

  start_ms="$(place_runner_current_time_ms)" || return 2
  deadline_ms=$((start_ms + duration_ms))

  place_runner_trace "live_burst_schedule segment=${segment} mode=bounded-burst duration_ms=${duration_ms} burst_count=${burst_count} burst_delay_ms=${delay_ms} safety_margin_ms=${safety_margin_ms} point=PACK_CLICK_POINT"
  input_click_current_burst "$burst_count" "$delay_ms" || return 2

  now_ms="$(place_runner_current_time_ms)" || return 2
  if test "$now_ms" -lt "$deadline_ms"; then
    remaining_ms=$((deadline_ms - now_ms))
    sleep_duration "${remaining_ms}ms" || return 2
    return 0
  fi

  overrun_ms=$((now_ms - deadline_ms))
  if test "$overrun_ms" -gt 0; then
    place_runner_trace "live_burst_overrun segment=${segment} overrun_ms=${overrun_ms}"
  fi
}

place_runner_run_click_schedule() {
  local segment="$1"
  local duration_key="$2"
  local duration
  local interval
  local duration_ms
  local interval_ms
  local clicks
  local i
  local elapsed_ms=0
  local remaining_ms
  local sleep_ms

  duration="$(place_runner_get_timing "$duration_key")" || return 2
  interval="$(place_runner_get_timing PLACE_CLICK_INTERVAL)" || return 2
  duration_ms="$(parse_duration_ms "$duration")" || return 2
  interval_ms="$(parse_duration_ms "$interval")" || return 2
  clicks="$(place_runner_calculate_click_count "$duration_ms" "$interval_ms")" || return 2

  place_runner_trace "click_schedule segment=${segment} duration_ms=${duration_ms} interval_ms=${interval_ms} clicks=${clicks} point=PACK_CLICK_POINT click_mode=current-position"

  for ((i = 1; i <= clicks; i++)); do
    place_runner_trace "click_schedule segment=${segment} click_index=${i}/${clicks} point=PACK_CLICK_POINT click_mode=current-position"
    input_click_current || return 2

    remaining_ms=$((duration_ms - elapsed_ms))
    if test "$remaining_ms" -le 0; then
      continue
    fi

    if test "$remaining_ms" -gt "$interval_ms"; then
      sleep_ms="$interval_ms"
    else
      sleep_ms="$remaining_ms"
    fi

    input_sleep "${sleep_ms}ms" || return 2
    elapsed_ms=$((elapsed_ms + sleep_ms))
  done
}

place_runner_preflight() {
  local failures=0

  place_runner_validate_required_points || failures=$((failures + 1))
  place_runner_validate_required_timing || failures=$((failures + 1))

  test "$failures" -eq 0
}

place_runner_run() {
  local base_count
  local i
  local forward_duration
  local left_duration
  local mode
  local segment_status

  mode="$(input_mode)" || return 2

  place_runner_load_context || return $?
  place_runner_preflight || return $?

  base_count="$(place_runner_get_timing BASE_PRESS_COUNT_NORMAL)" || return 2
  forward_duration="$(place_runner_get_timing PLACE_FORWARD_DURATION)" || return 2
  left_duration="$(place_runner_get_timing PLACE_LEFT_DURATION)" || return 2

  place_runner_trace "start"
  release_all_inputs || return 2

  place_runner_trace "base_teleport count=${base_count}"
  for ((i = 1; i <= base_count; i++)); do
    place_runner_trace "base_teleport click_index=${i}/${base_count} point=BASE_TELEPORT_BUTTON"
    place_runner_click_named_point BASE_TELEPORT_BUTTON || return 2
    input_sleep "$(place_runner_get_timing BASE_PRESS_DELAY)" || return 2
  done

  input_sleep "$(place_runner_get_timing POST_BASE_WAIT)" || return 2

  place_runner_trace "select_pack point=PACK_CLICK_POINT"
  place_runner_click_named_point PACK_CLICK_POINT || return 2

  place_runner_trace "place_path forward duration=${forward_duration}"
  place_runner_move_to_placement_target || return 2
  keydown w || return 2
  segment_status=0
  if test "$mode" = "live"; then
    place_runner_run_live_click_burst forward PLACE_FORWARD_DURATION || segment_status=$?
  else
    place_runner_run_click_schedule forward PLACE_FORWARD_DURATION || segment_status=$?
  fi
  keyup w || return 2
  if test "$segment_status" -ne 0; then
    return "$segment_status"
  fi

  place_runner_trace "place_path left duration=${left_duration}"
  place_runner_move_to_placement_target || return 2
  keydown a || return 2
  segment_status=0
  if test "$mode" = "live"; then
    place_runner_run_live_click_burst left PLACE_LEFT_DURATION || segment_status=$?
  else
    place_runner_run_click_schedule left PLACE_LEFT_DURATION || segment_status=$?
  fi
  keyup a || return 2
  if test "$segment_status" -ne 0; then
    return "$segment_status"
  fi

  input_sleep "$(place_runner_get_timing POST_PLACE_WAIT)" || return 2
  release_all_inputs || return 2
  place_runner_trace "complete"
}

place_runner_usage() {
  printf 'Usage: %s --dry-run\n' "$0" >&2
  printf '       %s --live\n' "$0" >&2
}

place_runner_require_live_gate() {
  if test "${MACRO_INPUT_MODE:-}" != "live" ||
    test "${MACRO_LIVE_INPUT_ALLOWED:-}" != "1" ||
    test "${MACRO_PLACE_RUNNER_LIVE_CONFIRM:-}" != "YES"; then
    printf 'ERROR: live place runner blocked: set MACRO_INPUT_MODE=live MACRO_LIVE_INPUT_ALLOWED=1 MACRO_PLACE_RUNNER_LIVE_CONFIRM=YES\n' >&2
    return 2
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:---dry-run}" in
    --dry-run)
      shift || true
      if test "$#" -ne 0; then
        place_runner_usage
        exit 2
      fi
      export MACRO_INPUT_MODE=dry-run
      place_runner_run
      ;;
    --live)
      shift || true
      if test "$#" -ne 0; then
        place_runner_usage
        exit 2
      fi
      place_runner_require_live_gate
      place_runner_run
      ;;
    *)
      place_runner_usage
      exit 2
      ;;
  esac
fi
