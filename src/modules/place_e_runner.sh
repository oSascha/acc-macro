#!/usr/bin/env bash

place_e_runner_script="${BASH_SOURCE[0]}"
place_e_runner_dir="${place_e_runner_script%/*}"
if test "$place_e_runner_dir" = "$place_e_runner_script"; then
  place_e_runner_dir="."
fi

place_e_runner_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$place_e_runner_project_root"; then
  place_e_runner_project_root="$(cd "$place_e_runner_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$place_e_runner_project_root/src/lib/config.sh"
# shellcheck source=../lib/points.sh
. "$place_e_runner_project_root/src/lib/points.sh"
# shellcheck source=../lib/input.sh
. "$place_e_runner_project_root/src/lib/input.sh"

place_e_runner_trace() {
  printf 'TRACE place-e-runner %s\n' "$*"
}

place_e_runner_load_context() {
  local runtime_dir
  local points_file="${PLACE_E_RUNNER_POINTS_FILE:-}"
  local timing_file="${PLACE_E_RUNNER_TIMING_FILE:-}"

  if test -z "$points_file" || test -z "$timing_file"; then
    runtime_dir="$(config_pack_opener_dir)"
    config_bootstrap_pack_opener_from_templates
    points_file="${points_file:-$runtime_dir/points.conf}"
    timing_file="${timing_file:-$runtime_dir/timing.conf}"
  fi

  points_load "$points_file"
  timing_load "$timing_file"
}

place_e_runner_get_timing() {
  local key="${1:-}"
  local value

  if test -z "$key"; then
    printf 'ERROR: place_e_runner_get_timing requires a timing key\n' >&2
    return 2
  fi

  if value="$(timing_get "$key" 2>/dev/null)"; then
    printf '%s\n' "$value"
    return 0
  fi

  case "$key" in
    PLACE_CLICK_INTERVAL|PLACE_E_INTERVAL)
      printf '100ms\n'
      return 0
      ;;
    PLACE_E_HOLD_DURATION)
      printf '20ms\n'
      return 0
      ;;
    PLACE_LIVE_CLICK_INTERVAL)
      printf '1ms\n'
      return 0
      ;;
    PLACE_LIVE_CLICK_BURST_DELAY)
      printf '1ms\n'
      return 0
      ;;
    PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN)
      printf '20ms\n'
      return 0
      ;;
    PLACE_LIVE_E_INTERVAL)
      printf '25ms\n'
      return 0
      ;;
  esac

  timing_get "$key"
}

place_e_runner_validate_required_points() {
  local point
  local failures=0

  for point in BASE_TELEPORT_BUTTON PACK_CLICK_POINT; do
    if points_get "$point" >/dev/null; then
      printf 'OK: place+E runner point %s = %s\n' "$point" "$(points_get "$point")"
    else
      failures=$((failures + 1))
    fi
  done

  test "$failures" -eq 0
}

place_e_runner_validate_count_timing() {
  local key="$1"
  local value

  value="$(place_e_runner_get_timing "$key")" || return 2
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: place+E runner timing %s must be a non-negative integer: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf 'OK: place+E runner timing %s = %s\n' "$key" "$value"
}

place_e_runner_validate_duration_timing() {
  local key="$1"
  local require_positive="${2:-0}"
  local value
  local ms

  value="$(place_e_runner_get_timing "$key")" || return 2
  ms="$(parse_duration_ms "$value")" || return 2

  if test "$require_positive" = "1" && test "$ms" -le 0; then
    printf 'ERROR: place+E runner timing %s must be greater than 0: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf 'OK: place+E runner timing %s = %s (%sms)\n' "$key" "$value" "$ms"
}

place_e_runner_validate_required_timing() {
  local failures=0

  place_e_runner_validate_count_timing BASE_PRESS_COUNT_NORMAL || failures=$((failures + 1))
  place_e_runner_validate_duration_timing BASE_PRESS_DELAY 0 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing POST_BASE_WAIT 0 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing PLACE_FORWARD_DURATION 1 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing PLACE_LEFT_DURATION 1 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing POST_PLACE_WAIT 0 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing PLACE_CLICK_INTERVAL 1 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing PLACE_E_INTERVAL 1 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing PLACE_E_HOLD_DURATION 1 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing PLACE_LIVE_CLICK_INTERVAL 1 || failures=$((failures + 1))
  place_e_runner_validate_duration_timing PLACE_LIVE_E_INTERVAL 1 || failures=$((failures + 1))

  test "$failures" -eq 0
}

place_e_runner_resolve_point() {
  local name="${1:-}"

  if test -z "$name"; then
    printf 'ERROR: place_e_runner_resolve_point requires a point name\n' >&2
    return 2
  fi

  points_get "$name"
}

place_e_runner_click_named_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(place_e_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  place_e_runner_trace "click point=${name} x=${x} y=${y}"
  click_point "$x" "$y"
}

place_e_runner_move_named_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(place_e_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  place_e_runner_trace "move point=${name} x=${x} y=${y}"
  move_mouse "$x" "$y"
}

place_e_runner_trace_named_point() {
  local event="$1"
  local name="$2"
  local point
  local x
  local y

  point="$(place_e_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  place_e_runner_trace "${event} point=${name} x=${x} y=${y}"
}

place_e_runner_move_to_placement_target() {
  place_e_runner_trace_named_point placement_target PACK_CLICK_POINT || return $?
  place_e_runner_move_named_point PACK_CLICK_POINT
}

place_e_runner_calculate_count() {
  local duration_ms="${1:-}"
  local interval_ms="${2:-}"

  if ! [[ "$duration_ms" =~ ^[0-9]+$ ]] || ! [[ "$interval_ms" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: schedule count inputs must be non-negative integers\n' >&2
    return 2
  fi

  if test "$interval_ms" -le 0; then
    printf 'ERROR: schedule interval must be greater than 0\n' >&2
    return 2
  fi

  printf '%s\n' "$(((duration_ms + interval_ms - 1) / interval_ms))"
}

place_e_runner_current_time_ms() {
  date +%s%3N
}

place_e_runner_duration_to_ms() {
  parse_duration_ms "${1:-}"
}

place_e_runner_live_interval_ms() {
  local key="$1"
  local value
  local value_ms

  value="$(place_e_runner_get_timing "$key")" || return 2
  value_ms="$(place_e_runner_duration_to_ms "$value")" || return 2

  if test "$value_ms" -le 0; then
    printf 'ERROR: %s must be greater than 0: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf '%s\n' "$value_ms"
}

place_e_runner_live_sleep_until() {
  local deadline_ms="$1"
  local next_event_ms="$2"
  local now_ms
  local target_ms
  local sleep_ms

  now_ms="$(place_e_runner_current_time_ms)" || return 2
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

place_e_runner_run_e_tap() {
  local segment="$1"
  local index="$2"
  local total="$3"
  local hold="$4"

  place_e_runner_trace "e_tap segment=${segment} index=${index}/${total} hold=${hold}"
  keydown e || return 2
  input_sleep "$hold" || return 2
  keyup e || return 2
}

place_e_runner_run_live_e_tap() {
  local segment="$1"
  local index="$2"
  local hold="$3"

  place_e_runner_trace "live_e_tap segment=${segment} index=${index} hold=${hold}"
  keydown e || return 2
  input_sleep "$hold" || return 2
  keyup e || return 2
}

place_e_runner_min_ms() {
  local left="$1"
  local right="$2"

  if test "$left" -le "$right"; then
    printf '%s\n' "$left"
  else
    printf '%s\n' "$right"
  fi
}

place_e_runner_print_live_schedule_plan() {
  local segment="$1"
  local duration_key="$2"
  local duration
  local e_hold
  local duration_ms
  local click_interval_ms
  local e_interval_ms
  local e_hold_ms

  duration="$(place_e_runner_get_timing "$duration_key")" || return 2
  e_hold="$(place_e_runner_get_timing PLACE_E_HOLD_DURATION)" || return 2

  duration_ms="$(place_e_runner_duration_to_ms "$duration")" || return 2
  click_interval_ms="$(place_e_runner_live_interval_ms PLACE_LIVE_CLICK_INTERVAL)" || return 2
  e_interval_ms="$(place_e_runner_live_interval_ms PLACE_LIVE_E_INTERVAL)" || return 2
  e_hold_ms="$(place_e_runner_duration_to_ms "$e_hold")" || return 2

  place_e_runner_trace "live_schedule_plan segment=${segment} mode=deadline duration_ms=${duration_ms} click_interval_ms=${click_interval_ms} e_interval_ms=${e_interval_ms} e_hold_ms=${e_hold_ms} point=PACK_CLICK_POINT click_mode=current-position"
}

place_e_runner_run_live_combined_schedule() {
  local segment="$1"
  local duration_key="$2"
  local duration
  local e_hold
  local duration_ms
  local click_interval_ms
  local e_interval_ms
  local e_hold_ms
  local start_ms
  local deadline_ms
  local next_click_ms
  local next_e_ms
  local now_ms
  local next_event_ms
  local remaining_ms
  local click_index=1
  local e_index=1
  local did_event

  duration="$(place_e_runner_get_timing "$duration_key")" || return 2
  e_hold="$(place_e_runner_get_timing PLACE_E_HOLD_DURATION)" || return 2

  duration_ms="$(place_e_runner_duration_to_ms "$duration")" || return 2
  click_interval_ms="$(place_e_runner_live_interval_ms PLACE_LIVE_CLICK_INTERVAL)" || return 2
  e_interval_ms="$(place_e_runner_live_interval_ms PLACE_LIVE_E_INTERVAL)" || return 2
  e_hold_ms="$(place_e_runner_duration_to_ms "$e_hold")" || return 2

  start_ms="$(place_e_runner_current_time_ms)" || return 2
  deadline_ms=$((start_ms + duration_ms))
  next_click_ms="$start_ms"
  next_e_ms="$start_ms"

  place_e_runner_trace "live_schedule segment=${segment} mode=deadline duration_ms=${duration_ms} click_interval_ms=${click_interval_ms} e_interval_ms=${e_interval_ms} e_hold_ms=${e_hold_ms}"

  while true; do
    now_ms="$(place_e_runner_current_time_ms)" || return 2
    if test "$now_ms" -ge "$deadline_ms"; then
      break
    fi

    did_event=0

    if test "$now_ms" -ge "$next_click_ms"; then
      remaining_ms=$((deadline_ms - now_ms))
      place_e_runner_trace "live_schedule segment=${segment} click_index=${click_index} point=PACK_CLICK_POINT click_mode=current-position remaining_ms=${remaining_ms}"
      input_click_current || return 2
      click_index=$((click_index + 1))
      now_ms="$(place_e_runner_current_time_ms)" || return 2
      next_click_ms=$((now_ms + click_interval_ms))
      did_event=1
    fi

    if test "$now_ms" -ge "$deadline_ms"; then
      continue
    fi

    if test "$now_ms" -ge "$next_e_ms"; then
      remaining_ms=$((deadline_ms - now_ms))
      if test "$remaining_ms" -ge "$e_hold_ms"; then
        place_e_runner_run_live_e_tap "$segment" "$e_index" "$e_hold" || return 2
        e_index=$((e_index + 1))
        now_ms="$(place_e_runner_current_time_ms)" || return 2
        next_e_ms=$((now_ms + e_interval_ms))
        did_event=1
      else
        next_e_ms="$deadline_ms"
      fi
    fi

    if test "$did_event" -eq 1; then
      continue
    fi

    next_event_ms="$(place_e_runner_min_ms "$next_click_ms" "$next_e_ms")"
    place_e_runner_live_sleep_until "$deadline_ms" "$next_event_ms" || return 2
  done
}

place_e_runner_run_combined_schedule() {
  local segment="$1"
  local duration_key="$2"
  local duration
  local click_interval
  local e_interval
  local e_hold
  local duration_ms
  local click_interval_ms
  local e_interval_ms
  local e_hold_ms
  local placement_clicks
  local e_taps
  local click_index=1
  local e_index=1
  local next_click_ms=0
  local next_e_ms=0
  local current_ms=0
  local next_event_ms
  local sleep_ms

  duration="$(place_e_runner_get_timing "$duration_key")" || return 2
  click_interval="$(place_e_runner_get_timing PLACE_CLICK_INTERVAL)" || return 2
  e_interval="$(place_e_runner_get_timing PLACE_E_INTERVAL)" || return 2
  e_hold="$(place_e_runner_get_timing PLACE_E_HOLD_DURATION)" || return 2

  duration_ms="$(parse_duration_ms "$duration")" || return 2
  click_interval_ms="$(parse_duration_ms "$click_interval")" || return 2
  e_interval_ms="$(parse_duration_ms "$e_interval")" || return 2
  e_hold_ms="$(parse_duration_ms "$e_hold")" || return 2

  placement_clicks="$(place_e_runner_calculate_count "$duration_ms" "$click_interval_ms")" || return 2
  e_taps="$(place_e_runner_calculate_count "$duration_ms" "$e_interval_ms")" || return 2

  place_e_runner_trace "schedule segment=${segment} duration_ms=${duration_ms} click_interval_ms=${click_interval_ms} e_interval_ms=${e_interval_ms} e_hold_ms=${e_hold_ms} placement_clicks=${placement_clicks} e_taps=${e_taps} point=PACK_CLICK_POINT click_mode=current-position"

  while test "$click_index" -le "$placement_clicks" || test "$e_index" -le "$e_taps"; do
    if test "$click_index" -le "$placement_clicks" && test "$e_index" -le "$e_taps"; then
      next_event_ms="$(place_e_runner_min_ms "$next_click_ms" "$next_e_ms")"
    elif test "$click_index" -le "$placement_clicks"; then
      next_event_ms="$next_click_ms"
    else
      next_event_ms="$next_e_ms"
    fi

    if test "$next_event_ms" -gt "$current_ms"; then
      sleep_ms=$((next_event_ms - current_ms))
      input_sleep "${sleep_ms}ms" || return 2
      current_ms="$next_event_ms"
    fi

    if test "$click_index" -le "$placement_clicks" && test "$next_click_ms" -le "$current_ms"; then
      place_e_runner_trace "schedule segment=${segment} click_index=${click_index}/${placement_clicks} point=PACK_CLICK_POINT click_mode=current-position"
      input_click_current || return 2
      click_index=$((click_index + 1))
      next_click_ms=$((next_click_ms + click_interval_ms))
    fi

    if test "$e_index" -le "$e_taps" && test "$next_e_ms" -le "$current_ms"; then
      place_e_runner_run_e_tap "$segment" "$e_index" "$e_taps" "$e_hold" || return 2
      e_index=$((e_index + 1))
      next_e_ms=$((next_e_ms + e_interval_ms))
      current_ms=$((current_ms + e_hold_ms))
    fi
  done

  if test "$current_ms" -lt "$duration_ms"; then
    input_sleep "$((duration_ms - current_ms))ms" || return 2
  fi
}

place_e_runner_preflight() {
  local failures=0

  place_e_runner_validate_required_points || failures=$((failures + 1))
  place_e_runner_validate_required_timing || failures=$((failures + 1))

  test "$failures" -eq 0
}

place_e_runner_run() {
  local base_count
  local i
  local forward_duration
  local left_duration
  local mode

  mode="$(input_mode)" || return 2
  if test "$mode" = "live"; then
    place_e_runner_require_live_gate || return 2
  fi

  place_e_runner_load_context || return $?
  place_e_runner_preflight || return $?

  base_count="$(place_e_runner_get_timing BASE_PRESS_COUNT_NORMAL)" || return 2
  forward_duration="$(place_e_runner_get_timing PLACE_FORWARD_DURATION)" || return 2
  left_duration="$(place_e_runner_get_timing PLACE_LEFT_DURATION)" || return 2

  place_e_runner_trace "start"
  release_all_inputs || return 2

  place_e_runner_trace "base_teleport count=${base_count}"
  for ((i = 1; i <= base_count; i++)); do
    place_e_runner_trace "base_teleport click_index=${i}/${base_count} point=BASE_TELEPORT_BUTTON"
    place_e_runner_click_named_point BASE_TELEPORT_BUTTON || return 2
    input_sleep "$(place_e_runner_get_timing BASE_PRESS_DELAY)" || return 2
  done

  input_sleep "$(place_e_runner_get_timing POST_BASE_WAIT)" || return 2

  place_e_runner_trace "select_pack point=PACK_CLICK_POINT"
  place_e_runner_click_named_point PACK_CLICK_POINT || return 2

  place_e_runner_trace "segment=forward movement_key=w duration=${forward_duration}"
  place_e_runner_move_to_placement_target || return 2
  keydown w || return 2
  if test "$mode" = "live"; then
    place_e_runner_run_live_combined_schedule forward PLACE_FORWARD_DURATION || return 2
  else
    place_e_runner_run_combined_schedule forward PLACE_FORWARD_DURATION || return 2
  fi
  keyup w || return 2

  place_e_runner_trace "segment=left movement_key=a duration=${left_duration}"
  place_e_runner_move_to_placement_target || return 2
  keydown a || return 2
  if test "$mode" = "live"; then
    place_e_runner_run_live_combined_schedule left PLACE_LEFT_DURATION || return 2
  else
    place_e_runner_run_combined_schedule left PLACE_LEFT_DURATION || return 2
  fi
  keyup a || return 2

  input_sleep "$(place_e_runner_get_timing POST_PLACE_WAIT)" || return 2
  release_all_inputs || return 2
  place_e_runner_trace "complete"
}

place_e_runner_usage() {
  printf 'Usage: %s --dry-run\n' "$0" >&2
  printf '       %s --live\n' "$0" >&2
}

place_e_runner_require_live_gate() {
  if test "${MACRO_INPUT_MODE:-}" != "live" ||
    test "${MACRO_LIVE_INPUT_ALLOWED:-}" != "1" ||
    test "${MACRO_PLACE_E_RUNNER_LIVE_CONFIRM:-}" != "YES"; then
    printf 'ERROR: live place+E runner blocked: set MACRO_INPUT_MODE=live MACRO_LIVE_INPUT_ALLOWED=1 MACRO_PLACE_E_RUNNER_LIVE_CONFIRM=YES\n' >&2
    return 2
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:---dry-run}" in
    --dry-run)
      shift || true
      if test "$#" -ne 0; then
        place_e_runner_usage
        exit 2
      fi
      export MACRO_INPUT_MODE=dry-run
      place_e_runner_run
      ;;
    --live)
      shift || true
      if test "$#" -ne 0; then
        place_e_runner_usage
        exit 2
      fi
      place_e_runner_require_live_gate
      place_e_runner_run
      ;;
    *)
      place_e_runner_usage
      exit 2
      ;;
  esac
fi
