#!/usr/bin/env bash

live_cycle_runner_script="${BASH_SOURCE[0]}"
live_cycle_runner_dir="${live_cycle_runner_script%/*}"
if test "$live_cycle_runner_dir" = "$live_cycle_runner_script"; then
  live_cycle_runner_dir="."
fi

live_cycle_runner_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$live_cycle_runner_project_root"; then
  live_cycle_runner_project_root="$(cd "$live_cycle_runner_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$live_cycle_runner_project_root/src/lib/config.sh"
# shellcheck source=../lib/points.sh
. "$live_cycle_runner_project_root/src/lib/points.sh"
# shellcheck source=../lib/potion_plan.sh
. "$live_cycle_runner_project_root/src/lib/potion_plan.sh"
# shellcheck source=../lib/input.sh
. "$live_cycle_runner_project_root/src/lib/input.sh"
# shellcheck source=potion_runner.sh
. "$live_cycle_runner_project_root/src/modules/potion_runner.sh"

LIVE_CYCLE_RUNNER_MAX_CYCLES="${LIVE_CYCLE_RUNNER_MAX_CYCLES:-3}"
LIVE_CYCLE_RUNNER_DEFAULT_CYCLES=1
# Live cycle tests cannot open packs without potions, so potions run by default.
LIVE_CYCLE_RUNNER_DEFAULT_POTIONS=1
LIVE_CYCLE_RUNNER_E_TAP_MAX="${LIVE_CYCLE_RUNNER_E_TAP_MAX:-100}"

# Module-level handles tracking the currently-running segment's supervised
# workers and movement key. The emergency EXIT trap (live mode only) reads these
# to guarantee worker reaping and key release if the process dies mid-segment.
__live_cycle_runner_active_movement_key=""
__live_cycle_runner_active_click_pid=""
__live_cycle_runner_active_e_pid=""
__lcr_transition_start_ms=""

# Cycle-loop context cache: populated once by live_cycle_runner_prepare_context
# before the first cycle and reused every iteration to eliminate per-cycle
# subshell forks for timing and point lookups.
__lcr_prepared=0
__lcr_base_count=""
__lcr_base_press_delay=""
__lcr_post_base_wait=""
__lcr_post_place_wait=""
__lcr_forward_value=""
__lcr_left_value=""
__lcr_placement_params=""
__lcr_pack_x=""
__lcr_pack_y=""
# Set to the current cycle number before each placement call so sub-phase
# timing traces inside the placement functions can emit the cycle label.
__lcr_timing_cycle=""
# Set at the end of each cycle so the next cycle can emit a between-cycles gap.
__lcr_prev_cycle_end_ms=""

live_cycle_runner_trace() {
  if acc_trace_enabled; then
    printf 'TRACE live-cycle-runner %s\n' "$*"
  fi
}

live_cycle_runner_now_ms() {
  date +%s%3N
}

live_cycle_runner_min() {
  if test "$1" -le "$2"; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$2"
  fi
}

live_cycle_runner_load_context() {
  local runtime_dir
  local points_file="${LIVE_CYCLE_RUNNER_POINTS_FILE:-}"
  local timing_file="${LIVE_CYCLE_RUNNER_TIMING_FILE:-}"
  local potion_plan_file="${LIVE_CYCLE_RUNNER_POTION_PLAN_FILE:-}"

  if test -z "$points_file" || test -z "$timing_file" || test -z "$potion_plan_file"; then
    runtime_dir="$(config_pack_opener_dir)"
    config_bootstrap_pack_opener_from_templates
    points_file="${points_file:-$runtime_dir/points.conf}"
    timing_file="${timing_file:-$runtime_dir/timing.conf}"
    potion_plan_file="${potion_plan_file:-$(config_pack_opener_potion_plan_file)}"
  fi

  # Let the optional potion runner reuse the same config files.
  export POTION_RUNNER_POINTS_FILE="${POTION_RUNNER_POINTS_FILE:-$points_file}"
  export POTION_RUNNER_TIMING_FILE="${POTION_RUNNER_TIMING_FILE:-$timing_file}"
  export POTION_RUNNER_POTION_PLAN_FILE="${POTION_RUNNER_POTION_PLAN_FILE:-$potion_plan_file}"

  points_load "$points_file"
  timing_load "$timing_file"
  potion_plan_load "$potion_plan_file"
}

live_cycle_runner_get_timing() {
  local key="${1:-}"
  local value

  if test -z "$key"; then
    printf 'ERROR: live_cycle_runner_get_timing requires a timing key\n' >&2
    return 2
  fi

  if value="$(timing_get "$key" 2>/dev/null)"; then
    printf '%s\n' "$value"
    return 0
  fi

  case "$key" in
    PLACE_LIVE_CLICK_BURST_DELAY)
      printf '1ms\n'
      return 0
      ;;
    PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN)
      printf '20ms\n'
      return 0
      ;;
    PLACE_LIVE_CLICK_WORKER_CHUNK_MS)
      printf '120ms\n'
      return 0
      ;;
    PLACE_LIVE_E_INTERVAL)
      printf '10ms\n'
      return 0
      ;;
    PLACE_LIVE_E_WORKER_CHUNK_MS)
      printf '80ms\n'
      return 0
      ;;
    PLACE_LIVE_E_ENABLED)
      printf '1\n'
      return 0
      ;;
    PLACE_LIVE_WORKER_STOP_GRACE_MS)
      printf '50ms\n'
      return 0
      ;;
  esac

  timing_get "$key"
}

live_cycle_runner_timing_ms() {
  local key="${1:-}"
  local value

  value="$(live_cycle_runner_get_timing "$key")" || return 2
  parse_duration_ms "$value"
}

live_cycle_runner_resolve_point() {
  local name="${1:-}"

  if test -z "$name"; then
    printf 'ERROR: live_cycle_runner_resolve_point requires a point name\n' >&2
    return 2
  fi

  points_get "$name"
}

live_cycle_runner_click_named_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(live_cycle_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  live_cycle_runner_trace "click point=${name} x=${x} y=${y}"
  click_point "$x" "$y"
}

live_cycle_runner_move_named_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(live_cycle_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  live_cycle_runner_trace "move point=${name} x=${x} y=${y}"
  move_mouse "$x" "$y"
}

live_cycle_runner_validate_required_points() {
  local point
  local failures=0

  for point in BASE_TELEPORT_BUTTON PACK_CLICK_POINT; do
    if points_get "$point" >/dev/null; then
      printf 'OK: live cycle runner point %s = %s\n' "$point" "$(points_get "$point")"
    else
      failures=$((failures + 1))
    fi
  done

  test "$failures" -eq 0
}

live_cycle_runner_validate_count_timing() {
  local key="$1"
  local value

  value="$(live_cycle_runner_get_timing "$key")" || return 2
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: live cycle runner timing %s must be a non-negative integer: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf 'OK: live cycle runner timing %s = %s\n' "$key" "$value"
}

live_cycle_runner_validate_bool_timing() {
  local key="$1"
  local value

  value="$(live_cycle_runner_get_timing "$key")" || return 2
  if ! [[ "$value" =~ ^(0|1)$ ]]; then
    printf 'ERROR: live cycle runner timing %s must be 0 or 1: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf 'OK: live cycle runner timing %s = %s\n' "$key" "$value"
}

live_cycle_runner_validate_duration_timing() {
  local key="$1"
  local require_positive="${2:-0}"
  local value
  local ms

  value="$(live_cycle_runner_get_timing "$key")" || return 2
  ms="$(parse_duration_ms "$value")" || return 2

  if test "$require_positive" = "1" && test "$ms" -le 0; then
    printf 'ERROR: live cycle runner timing %s must be greater than 0: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf 'OK: live cycle runner timing %s = %s (%sms)\n' "$key" "$value" "$ms"
}

live_cycle_runner_validate_required_timing() {
  local failures=0

  live_cycle_runner_validate_count_timing BASE_PRESS_COUNT_NORMAL || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing BASE_PRESS_DELAY 0 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing POST_BASE_WAIT 0 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing POST_SECOND_BASE_WAIT 0 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing PLACE_FORWARD_DURATION 1 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing PLACE_LEFT_DURATION 1 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing PLACE_LIVE_CLICK_BURST_DELAY 0 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN 0 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing PLACE_LIVE_CLICK_WORKER_CHUNK_MS 1 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing PLACE_LIVE_E_INTERVAL 1 || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing PLACE_LIVE_E_WORKER_CHUNK_MS 1 || failures=$((failures + 1))
  live_cycle_runner_validate_bool_timing PLACE_LIVE_E_ENABLED || failures=$((failures + 1))
  live_cycle_runner_validate_duration_timing PLACE_LIVE_WORKER_STOP_GRACE_MS 0 || failures=$((failures + 1))

  test "$failures" -eq 0
}

live_cycle_runner_preflight() {
  local failures=0

  live_cycle_runner_validate_required_points || failures=$((failures + 1))
  live_cycle_runner_validate_required_timing || failures=$((failures + 1))

  test "$failures" -eq 0
}

live_cycle_runner_parse_cycles() {
  local value="${1:-$LIVE_CYCLE_RUNNER_DEFAULT_CYCLES}"

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: cycles must be a positive integer: %s\n' "$value" >&2
    return 2
  fi

  if test "$value" -lt 1; then
    printf 'ERROR: cycles must be at least 1: %s\n' "$value" >&2
    return 2
  fi

  if ! [[ "$LIVE_CYCLE_RUNNER_MAX_CYCLES" =~ ^[0-9]+$ ]] ||
    test "$LIVE_CYCLE_RUNNER_MAX_CYCLES" -lt 1; then
    printf 'ERROR: LIVE_CYCLE_RUNNER_MAX_CYCLES must be a positive integer: %s\n' "$LIVE_CYCLE_RUNNER_MAX_CYCLES" >&2
    return 2
  fi

  if test "$value" -gt "$LIVE_CYCLE_RUNNER_MAX_CYCLES"; then
    printf 'ERROR: cycles %s exceeds max %s\n' "$value" "$LIVE_CYCLE_RUNNER_MAX_CYCLES" >&2
    return 2
  fi

  printf '%s\n' "$value"
}

live_cycle_runner_require_live_gate() {
  if test "${MACRO_INPUT_MODE:-}" != "live" ||
    test "${MACRO_LIVE_INPUT_ALLOWED:-}" != "1" ||
    test "${MACRO_LIVE_CYCLE_RUNNER_CONFIRM:-}" != "YES"; then
    printf 'ERROR: live cycle runner blocked: set MACRO_INPUT_MODE=live MACRO_LIVE_INPUT_ALLOWED=1 MACRO_LIVE_CYCLE_RUNNER_CONFIRM=YES\n' >&2
    return 2
  fi
}

live_cycle_runner_click_burst_count() {
  local usable_ms="$1"
  local delay_ms="$2"
  local count

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

live_cycle_runner_e_tap_count() {
  local chunk_ms="$1"
  local interval_ms="$2"
  local count

  count=$((chunk_ms / interval_ms))

  if test "$count" -gt "$LIVE_CYCLE_RUNNER_E_TAP_MAX"; then
    count="$LIVE_CYCLE_RUNNER_E_TAP_MAX"
  fi

  printf '%s\n' "$count"
}

# Gather every timing the concurrent segment needs, as one space-separated row:
# duration burst_delay safety_margin click_chunk e_enabled e_interval e_chunk grace
live_cycle_runner_segment_params() {
  local duration_key="$1"
  local duration_ms burst_delay_ms safety_margin_ms click_chunk_ms
  local e_enabled e_interval_ms e_chunk_ms grace_ms

  duration_ms="$(live_cycle_runner_timing_ms "$duration_key")" || return 2
  burst_delay_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_CLICK_BURST_DELAY)" || return 2
  safety_margin_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN)" || return 2
  click_chunk_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_CLICK_WORKER_CHUNK_MS)" || return 2
  e_enabled="$(live_cycle_runner_get_timing PLACE_LIVE_E_ENABLED)" || return 2
  e_interval_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_E_INTERVAL)" || return 2
  e_chunk_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_E_WORKER_CHUNK_MS)" || return 2
  grace_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_WORKER_STOP_GRACE_MS)" || return 2

  printf '%s %s %s %s %s %s %s %s\n' \
    "$duration_ms" "$burst_delay_ms" "$safety_margin_ms" "$click_chunk_ms" \
    "$e_enabled" "$e_interval_ms" "$e_chunk_ms" "$grace_ms"
}

live_cycle_runner_clear_active() {
  __live_cycle_runner_active_movement_key=""
  __live_cycle_runner_active_click_pid=""
  __live_cycle_runner_active_e_pid=""
}

# Best-effort cleanup installed as an EXIT trap in live mode only. It reaps any
# worker still tracked as active and releases all inputs so a process death
# mid-segment never leaves a worker running or a key/button stuck down.
live_cycle_runner_emergency_cleanup() {
  local pid

  for pid in "$__live_cycle_runner_active_click_pid" "$__live_cycle_runner_active_e_pid"; do
    if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  release_all_inputs 2>/dev/null || true
  live_cycle_runner_clear_active
}

# Bounded, segment-scoped left-click worker. Runs as a backgrounded function in
# live mode. It issues bounded foreground click bursts at the current cursor
# position until its worker deadline; it never loops past the deadline and never
# uses an unbounded xdotool repeat.
live_cycle_runner_click_worker() {
  local segment="$1"
  local worker_deadline_ms="$2"
  local burst_delay_ms="$3"
  local chunk_ms="$4"
  local now_ms remaining_ms usable_ms count
  local chunk_index=0

  while true; do
    now_ms="$(live_cycle_runner_now_ms)" || return 2
    if test "$now_ms" -ge "$worker_deadline_ms"; then
      break
    fi

    remaining_ms=$((worker_deadline_ms - now_ms))
    usable_ms="$(live_cycle_runner_min "$chunk_ms" "$remaining_ms")"
    if test "$usable_ms" -le 0; then
      break
    fi

    chunk_index=$((chunk_index + 1))
    count="$(live_cycle_runner_click_burst_count "$usable_ms" "$burst_delay_ms")" || return $?
    live_cycle_runner_trace "segment=${segment} worker=click chunk=${chunk_index} click_burst count=${count} delay_ms=${burst_delay_ms} usable_chunk_ms=${usable_ms} point=PACK_CLICK_POINT click_mode=current-position"
    input_click_current_burst "$count" "$burst_delay_ms" || return $?
  done

  return 0
}

# Bounded, segment-scoped E-tap worker. Runs as a backgrounded function in live
# mode, independent of the click worker, so E taps never consume click-burst
# time. Each iteration sends one bounded foreground E tap burst.
live_cycle_runner_e_worker() {
  local segment="$1"
  local deadline_ms="$2"
  local interval_ms="$3"
  local chunk_ms="$4"
  local now_ms remaining_ms eff_chunk_ms count
  local chunk_index=0

  while true; do
    now_ms="$(live_cycle_runner_now_ms)" || return 2
    if test "$now_ms" -ge "$deadline_ms"; then
      break
    fi

    remaining_ms=$((deadline_ms - now_ms))
    eff_chunk_ms="$(live_cycle_runner_min "$chunk_ms" "$remaining_ms")"
    count="$(live_cycle_runner_e_tap_count "$eff_chunk_ms" "$interval_ms")" || return $?
    if test "$count" -lt 1; then
      break
    fi

    chunk_index=$((chunk_index + 1))
    live_cycle_runner_trace "segment=${segment} worker=e chunk=${chunk_index} e_tap key=e count=${count} interval_ms=${interval_ms}"
    input_key_tap_burst e "$count" "$interval_ms" || return $?
  done

  return 0
}

# Bounded supervisor. Polls until both workers exit or until the grace window
# past the deadline elapses, then terminates any survivor. The loop is bounded
# by stop_ms, so it can never spin forever.
live_cycle_runner_supervise_workers() {
  local deadline_ms="$1"
  local grace_ms="$2"
  shift 2
  local pids=("$@")
  local stop_ms=$((deadline_ms + grace_ms))
  local now_ms alive pid

  while true; do
    now_ms="$(live_cycle_runner_now_ms)" || return 2

    alive=0
    for pid in "${pids[@]}"; do
      if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
        alive=1
      fi
    done

    if test "$alive" -eq 0; then
      break
    fi

    if test "$now_ms" -ge "$stop_ms"; then
      break
    fi

    sleep_duration "10ms" || true
  done

  for pid in "${pids[@]}"; do
    if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
      live_cycle_runner_trace "segment_worker_killed pid=${pid} reason=deadline_grace_exceeded"
      kill "$pid" 2>/dev/null || true
    fi
  done
}

# Live segment: hold the movement key while the bounded click worker and the
# bounded E worker run concurrently until the segment deadline. Movement keyup
# (and E keyup) are always attempted, even when a worker fails or is killed.
live_cycle_runner_run_segment_live() {
  local segment="$1"
  local movement_key="$2"
  local duration_key="$3"
  local params
  local duration_ms burst_delay_ms safety_margin_ms click_chunk_ms
  local e_enabled e_interval_ms e_chunk_ms grace_ms
  local start_ms deadline_ms worker_deadline_ms
  local click_pid="" e_pid="" click_status=0 e_status=0 status=0

  params="$(live_cycle_runner_segment_params "$duration_key")" || return 2
  read -r duration_ms burst_delay_ms safety_margin_ms click_chunk_ms \
    e_enabled e_interval_ms e_chunk_ms grace_ms <<< "$params"

  keydown "$movement_key" || return 2
  __live_cycle_runner_active_movement_key="$movement_key"

  start_ms="$(live_cycle_runner_now_ms)" || start_ms=""
  if test -z "$start_ms"; then
    keyup "$movement_key" || true
    live_cycle_runner_clear_active
    return 2
  fi

  deadline_ms=$((start_ms + duration_ms))
  worker_deadline_ms=$((deadline_ms - safety_margin_ms))
  if test "$worker_deadline_ms" -le "$start_ms"; then
    worker_deadline_ms="$deadline_ms"
  fi

  live_cycle_runner_click_worker "$segment" "$worker_deadline_ms" "$burst_delay_ms" "$click_chunk_ms" &
  click_pid=$!
  __live_cycle_runner_active_click_pid="$click_pid"

  if test "$e_enabled" = "1"; then
    live_cycle_runner_e_worker "$segment" "$deadline_ms" "$e_interval_ms" "$e_chunk_ms" &
    e_pid=$!
    __live_cycle_runner_active_e_pid="$e_pid"
    live_cycle_runner_trace "segment=${segment} mode=concurrent-click-e click_pid=${click_pid} e_pid=${e_pid} deadline_ms=${deadline_ms} worker_deadline_ms=${worker_deadline_ms}"
  else
    live_cycle_runner_trace "segment=${segment} mode=concurrent-click-e click_pid=${click_pid} e_pid=none deadline_ms=${deadline_ms} worker_deadline_ms=${worker_deadline_ms}"
  fi

  # Wait until the deadline, reaping survivors past the grace window.
  live_cycle_runner_supervise_workers "$deadline_ms" "$grace_ms" "$click_pid" "$e_pid"

  if test -n "$click_pid"; then
    wait "$click_pid" 2>/dev/null || click_status=$?
  fi
  if test -n "$e_pid"; then
    wait "$e_pid" 2>/dev/null || e_status=$?
  fi

  live_cycle_runner_clear_active

  # Guaranteed key release regardless of worker outcome.
  keyup "$movement_key" || status=2
  if test "$e_enabled" = "1"; then
    keyup e || status=2
  fi

  if test "$click_status" -ne 0; then
    live_cycle_runner_trace "segment=${segment} worker=click status=${click_status}"
    status="$click_status"
  fi
  if test "$e_status" -ne 0; then
    live_cycle_runner_trace "segment=${segment} worker=e status=${e_status}"
    if test "$status" -eq 0; then
      status="$e_status"
    fi
  fi

  live_cycle_runner_trace "segment=${segment} complete status=${status}"
  return "$status"
}

# Dry-run segment: never spawns workers. It simulates the concurrent plan,
# emits the worker simulation traces, and still exercises the bounded input
# primitives once each so timing math and option handling are validated.
live_cycle_runner_run_segment_simulated() {
  local segment="$1"
  local movement_key="$2"
  local duration_key="$3"
  local params
  local duration_ms burst_delay_ms safety_margin_ms click_chunk_ms
  local e_enabled e_interval_ms e_chunk_ms grace_ms
  local click_usable_ms click_count e_eff_chunk_ms e_count

  params="$(live_cycle_runner_segment_params "$duration_key")" || return 2
  read -r duration_ms burst_delay_ms safety_margin_ms click_chunk_ms \
    e_enabled e_interval_ms e_chunk_ms grace_ms <<< "$params"

  keydown "$movement_key" || return 2

  click_usable_ms="$(live_cycle_runner_min "$click_chunk_ms" "$duration_ms")"
  click_count="$(live_cycle_runner_click_burst_count "$click_usable_ms" "$burst_delay_ms")" || return 2
  live_cycle_runner_trace "segment=${segment} worker=click simulated=1 chunk_ms=${click_chunk_ms} burst_delay_ms=${burst_delay_ms} burst_count=${click_count} safety_margin_ms=${safety_margin_ms} grace_ms=${grace_ms} point=PACK_CLICK_POINT click_mode=current-position"
  input_click_current_burst "$click_count" "$burst_delay_ms" || return 2

  if test "$e_enabled" = "1"; then
    e_eff_chunk_ms="$(live_cycle_runner_min "$e_chunk_ms" "$duration_ms")"
    e_count="$(live_cycle_runner_e_tap_count "$e_eff_chunk_ms" "$e_interval_ms")" || return 2
    if test "$e_count" -lt 1; then
      e_count=1
    fi
    live_cycle_runner_trace "segment=${segment} worker=e simulated=1 interval_ms=${e_interval_ms} chunk_ms=${e_chunk_ms} tap_count=${e_count}"
    input_key_tap_burst e "$e_count" "$e_interval_ms" || return 2
  else
    live_cycle_runner_trace "segment=${segment} worker=e simulated=0 enabled=0"
  fi

  live_cycle_runner_trace "segment=${segment} mode=concurrent-click-e"

  keyup "$movement_key" || return 2
  live_cycle_runner_trace "segment=${segment} complete status=0"
}

# Move the cursor once to the active placement target, then run the segment in
# concurrent-live or simulated-dry mode depending on the input mode.
live_cycle_runner_run_segment() {
  local segment="$1"
  local movement_key="$2"
  local duration_key="$3"
  local mode

  mode="$(input_mode)" || return 2

  live_cycle_runner_move_named_point PACK_CLICK_POINT || return 2

  if test "$mode" = "live"; then
    live_cycle_runner_run_segment_live "$segment" "$movement_key" "$duration_key"
  else
    live_cycle_runner_run_segment_simulated "$segment" "$movement_key" "$duration_key"
  fi
}

# Gather every timing the continuous L-shape placement path needs, as one
# space-separated row:
# forward_ms left_ms total_ms burst_delay safety_margin click_chunk e_enabled
# e_interval e_chunk grace
live_cycle_runner_placement_params() {
  if test -n "${__lcr_placement_params:-}"; then
    printf '%s\n' "$__lcr_placement_params"
    return 0
  fi

  local forward_ms left_ms total_ms burst_delay_ms safety_margin_ms click_chunk_ms
  local e_enabled e_interval_ms e_chunk_ms grace_ms

  forward_ms="$(live_cycle_runner_timing_ms PLACE_FORWARD_DURATION)" || return 2
  left_ms="$(live_cycle_runner_timing_ms PLACE_LEFT_DURATION)" || return 2
  total_ms=$((forward_ms + left_ms))
  burst_delay_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_CLICK_BURST_DELAY)" || return 2
  safety_margin_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_CLICK_BURST_SAFETY_MARGIN)" || return 2
  click_chunk_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_CLICK_WORKER_CHUNK_MS)" || return 2
  e_enabled="$(live_cycle_runner_get_timing PLACE_LIVE_E_ENABLED)" || return 2
  e_interval_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_E_INTERVAL)" || return 2
  e_chunk_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_E_WORKER_CHUNK_MS)" || return 2
  grace_ms="$(live_cycle_runner_timing_ms PLACE_LIVE_WORKER_STOP_GRACE_MS)" || return 2

  printf '%s %s %s %s %s %s %s %s %s %s\n' \
    "$forward_ms" "$left_ms" "$total_ms" "$burst_delay_ms" "$safety_margin_ms" \
    "$click_chunk_ms" "$e_enabled" "$e_interval_ms" "$e_chunk_ms" "$grace_ms"
}

# Live placement path: ONE continuous click worker (and, when enabled, ONE
# continuous E worker) span the entire forward+left L-shape. The movement keys
# are held in the foreground for their durations, but the click worker is started
# once before forward and stopped once after left, so clicking never pauses at
# the forward->left transition. The path-level safety margin is applied exactly
# once (as the transition cushion), never per segment. Keys and workers are
# always cleaned up, even when a step fails.
live_cycle_runner_run_continuous_placement_live() {
  local forward_value="$1" left_value="$2"
  local params
  local forward_ms left_ms total_ms burst_delay_ms safety_margin_ms click_chunk_ms
  local e_enabled e_interval_ms e_chunk_ms grace_ms
  local start_ms cushion_ms worker_deadline_ms
  local click_pid="" e_pid="" click_status=0 e_status=0 status=0

  params="$(live_cycle_runner_placement_params)" || return 2
  read -r forward_ms left_ms total_ms burst_delay_ms safety_margin_ms \
    click_chunk_ms e_enabled e_interval_ms e_chunk_ms grace_ms <<< "$params"

  start_ms="$(live_cycle_runner_now_ms)" || return 2
  # Single, path-level application of the safety margin: it becomes the small
  # transition cushion that keeps the worker clicking across the forward->left
  # handoff and just past the final keyup. It is NOT applied once per segment.
  cushion_ms="$safety_margin_ms"
  worker_deadline_ms=$((start_ms + total_ms + cushion_ms))

  # Start ONE continuous click worker spanning the whole L-shape.
  live_cycle_runner_trace "placement worker=click start point=PACK_CLICK_POINT click_mode=current-position click_worker_scope=continuous_l_shape total_ms=${total_ms} cushion_ms=${cushion_ms} worker_deadline_ms=${worker_deadline_ms}"
  live_cycle_runner_click_worker placement "$worker_deadline_ms" "$burst_delay_ms" "$click_chunk_ms" &
  click_pid=$!
  __live_cycle_runner_active_click_pid="$click_pid"

  if test "$e_enabled" = "1"; then
    live_cycle_runner_trace "placement worker=e start interval_ms=${e_interval_ms} click_worker_scope=continuous_l_shape worker_deadline_ms=${worker_deadline_ms}"
    live_cycle_runner_e_worker placement "$worker_deadline_ms" "$e_interval_ms" "$e_chunk_ms" &
    e_pid=$!
    __live_cycle_runner_active_e_pid="$e_pid"
  fi

  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    local _setup_done_ms
    _setup_done_ms="$(live_cycle_runner_now_ms)"
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_setup duration_ms=$((_setup_done_ms - start_ms))"
  fi

  # Forward movement (W) held in the foreground while the workers run.
  live_cycle_runner_trace "movement segment=forward key=w duration_ms=${forward_ms}"
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_forward start_ms=$(live_cycle_runner_now_ms)"
  fi
  __live_cycle_runner_active_movement_key="w"
  keydown w || status=2
  if test "$status" -eq 0; then
    sleep_duration "$forward_value" || status=2
  fi
  keyup w || status=2
  __live_cycle_runner_active_movement_key=""
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    local _fwd_end_ms
    _fwd_end_ms="$(live_cycle_runner_now_ms)"
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_forward end_ms=${_fwd_end_ms} duration_ms=${forward_ms}"
  fi

  # Left movement (A) held in the foreground; the same click worker keeps running.
  if test "$status" -eq 0; then
    live_cycle_runner_trace "movement segment=left key=a duration_ms=${left_ms}"
    if test "${MACRO_TRACE_TIMING:-}" = "1"; then
      live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_left start_ms=$(live_cycle_runner_now_ms)"
    fi
    __live_cycle_runner_active_movement_key="a"
    keydown a || status=2
    if test "$status" -eq 0; then
      sleep_duration "$left_value" || status=2
    fi
    keyup a || status=2
    __live_cycle_runner_active_movement_key=""
    if test "${MACRO_TRACE_TIMING:-}" = "1"; then
      local _left_end_ms
      _left_end_ms="$(live_cycle_runner_now_ms)"
      live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_left end_ms=${_left_end_ms} duration_ms=${left_ms}"
    fi
  fi

  # Stop the continuous workers now that the full L-shape movement is done.
  live_cycle_runner_trace "placement worker=click stop"
  if test "$e_enabled" = "1"; then
    live_cycle_runner_trace "placement worker=e stop"
  fi
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    local _shutdown_start_ms
    _shutdown_start_ms="$(live_cycle_runner_now_ms)"
  fi
  live_cycle_runner_supervise_workers "$worker_deadline_ms" "$grace_ms" "$click_pid" "$e_pid"

  if test -n "$click_pid"; then
    wait "$click_pid" 2>/dev/null || click_status=$?
  fi
  if test -n "$e_pid"; then
    wait "$e_pid" 2>/dev/null || e_status=$?
  fi
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    local _shutdown_done_ms
    _shutdown_done_ms="$(live_cycle_runner_now_ms)"
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_worker_shutdown duration_ms=$((_shutdown_done_ms - _shutdown_start_ms))"
  fi

  live_cycle_runner_clear_active

  # Guaranteed key release regardless of worker outcome.
  keyup w || status=2
  keyup a || status=2
  if test "$e_enabled" = "1"; then
    keyup e || status=2
  fi

  if test "$click_status" -ne 0; then
    live_cycle_runner_trace "placement worker=click status=${click_status}"
    status="$click_status"
  fi
  if test "$e_status" -ne 0; then
    live_cycle_runner_trace "placement worker=e status=${e_status}"
    if test "$status" -eq 0; then
      status="$e_status"
    fi
  fi

  live_cycle_runner_trace "placement complete status=${status}"
  return "$status"
}

# Dry-run placement path: never spawns workers and never sleeps the real movement
# durations. It simulates the single continuous click worker (and optional E
# worker) spanning the whole L-shape, emits the same traces as the live path, and
# exercises the bounded input primitives once each so timing math is validated.
live_cycle_runner_run_continuous_placement_simulated() {
  local forward_value="$1" left_value="$2"
  local params
  local forward_ms left_ms total_ms burst_delay_ms safety_margin_ms click_chunk_ms
  local e_enabled e_interval_ms e_chunk_ms grace_ms
  local cushion_ms worker_span_ms click_usable_ms click_count e_eff_chunk_ms e_count

  params="$(live_cycle_runner_placement_params)" || return 2
  read -r forward_ms left_ms total_ms burst_delay_ms safety_margin_ms \
    click_chunk_ms e_enabled e_interval_ms e_chunk_ms grace_ms <<< "$params"

  cushion_ms="$safety_margin_ms"
  worker_span_ms=$((total_ms + cushion_ms))

  # One continuous click worker spans the full L-shape.
  live_cycle_runner_trace "placement worker=click start point=PACK_CLICK_POINT click_mode=current-position click_worker_scope=continuous_l_shape total_ms=${total_ms} cushion_ms=${cushion_ms}"
  click_usable_ms="$(live_cycle_runner_min "$click_chunk_ms" "$worker_span_ms")"
  click_count="$(live_cycle_runner_click_burst_count "$click_usable_ms" "$burst_delay_ms")" || return 2
  live_cycle_runner_trace "placement worker=click simulated=1 chunk_ms=${click_chunk_ms} burst_delay_ms=${burst_delay_ms} burst_count=${click_count} safety_margin_ms=${safety_margin_ms} grace_ms=${grace_ms} point=PACK_CLICK_POINT click_mode=current-position click_worker_scope=continuous_l_shape"
  input_click_current_burst "$click_count" "$burst_delay_ms" || return 2

  if test "$e_enabled" = "1"; then
    live_cycle_runner_trace "placement worker=e start interval_ms=${e_interval_ms} click_worker_scope=continuous_l_shape"
    e_eff_chunk_ms="$(live_cycle_runner_min "$e_chunk_ms" "$worker_span_ms")"
    e_count="$(live_cycle_runner_e_tap_count "$e_eff_chunk_ms" "$e_interval_ms")" || return 2
    if test "$e_count" -lt 1; then
      e_count=1
    fi
    live_cycle_runner_trace "placement worker=e simulated=1 interval_ms=${e_interval_ms} chunk_ms=${e_chunk_ms} tap_count=${e_count}"
    input_key_tap_burst e "$e_count" "$e_interval_ms" || return 2
  else
    live_cycle_runner_trace "placement worker=e simulated=0 enabled=0"
  fi

  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    local _sim_setup_done_ms
    _sim_setup_done_ms="$(live_cycle_runner_now_ms)"
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_setup duration_ms=0"
  fi

  # Forward then left movement (no real sleeps in dry-run); the click worker
  # spans both and is only stopped after the left segment.
  live_cycle_runner_trace "movement segment=forward key=w duration_ms=${forward_ms}"
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_forward start_ms=$(live_cycle_runner_now_ms) scheduled_ms=${forward_ms}"
  fi
  keydown w || return 2
  keyup w || return 2
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_forward end_ms=$(live_cycle_runner_now_ms) scheduled_ms=${forward_ms}"
  fi
  live_cycle_runner_trace "movement segment=left key=a duration_ms=${left_ms}"
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_left start_ms=$(live_cycle_runner_now_ms) scheduled_ms=${left_ms}"
  fi
  keydown a || return 2
  keyup a || return 2
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_left end_ms=$(live_cycle_runner_now_ms) scheduled_ms=${left_ms}"
  fi

  live_cycle_runner_trace "placement worker=click stop"
  if test "$e_enabled" = "1"; then
    live_cycle_runner_trace "placement worker=e stop"
  fi
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    live_cycle_runner_trace "timing cycle=${__lcr_timing_cycle:-?} phase=placement_worker_shutdown duration_ms=0"
  fi
  live_cycle_runner_trace "placement complete status=0"
}

# Move the cursor once to the active placement target, then run the whole
# forward+left L-shape under ONE continuous click worker (concurrent-live or
# simulated-dry depending on the input mode). No standalone pack-selection click
# is emitted; PACK_CLICK_POINT stays the active target.
live_cycle_runner_run_continuous_l_shape_placement() {
  local mode forward_value left_value

  mode="$(input_mode)" || return 2
  if test "${__lcr_prepared:-0}" = "1"; then
    forward_value="$__lcr_forward_value"
    left_value="$__lcr_left_value"
  else
    forward_value="$(live_cycle_runner_get_timing PLACE_FORWARD_DURATION)" || return 2
    left_value="$(live_cycle_runner_get_timing PLACE_LEFT_DURATION)" || return 2
  fi

  if test "${__lcr_prepared:-0}" = "1" && test -n "${__lcr_pack_x:-}" && test -n "${__lcr_pack_y:-}"; then
    live_cycle_runner_trace "move point=PACK_CLICK_POINT x=${__lcr_pack_x} y=${__lcr_pack_y}"
    move_mouse "$__lcr_pack_x" "$__lcr_pack_y" || return 2
  else
    live_cycle_runner_move_named_point PACK_CLICK_POINT || return 2
  fi

  if test "$mode" = "live"; then
    live_cycle_runner_run_continuous_placement_live "$forward_value" "$left_value"
  else
    live_cycle_runner_run_continuous_placement_simulated "$forward_value" "$left_value"
  fi
}

live_cycle_runner_prepare_context() {
  local _pack_point
  local _params

  __lcr_base_count="$(live_cycle_runner_get_timing BASE_PRESS_COUNT_NORMAL)" || return 2
  __lcr_base_press_delay="$(live_cycle_runner_get_timing BASE_PRESS_DELAY)" || return 2
  __lcr_post_base_wait="$(live_cycle_runner_get_timing POST_BASE_WAIT)" || return 2
  __lcr_post_place_wait="$(live_cycle_runner_get_timing POST_PLACE_WAIT)" || return 2
  __lcr_forward_value="$(live_cycle_runner_get_timing PLACE_FORWARD_DURATION)" || return 2
  __lcr_left_value="$(live_cycle_runner_get_timing PLACE_LEFT_DURATION)" || return 2
  _params="$(live_cycle_runner_placement_params)" || return 2
  __lcr_placement_params="$_params"
  _pack_point="$(live_cycle_runner_resolve_point PACK_CLICK_POINT)" || return 2
  __lcr_pack_x="${_pack_point%,*}"
  __lcr_pack_y="${_pack_point#*,}"

  __lcr_prepared=1
  live_cycle_runner_trace "context prepared base_count=${__lcr_base_count} forward=${__lcr_forward_value} left=${__lcr_left_value} pack=${__lcr_pack_x},${__lcr_pack_y}"
}

live_cycle_runner_teleport_to_base() {
  local cycle="$1"
  local label="$2"
  local wait_key="$3"
  local base_count
  local base_press_delay
  local i

  if test "${__lcr_prepared:-0}" = "1"; then
    base_count="$__lcr_base_count"
    base_press_delay="$__lcr_base_press_delay"
  else
    base_count="$(live_cycle_runner_get_timing BASE_PRESS_COUNT_NORMAL)" || return 2
    base_press_delay="$(live_cycle_runner_get_timing BASE_PRESS_DELAY)" || return 2
  fi
  live_cycle_runner_trace "cycle=${cycle} ${label} count=${base_count}"

  for ((i = 1; i <= base_count; i++)); do
    live_cycle_runner_trace "cycle=${cycle} ${label} click_index=${i}/${base_count} point=BASE_TELEPORT_BUTTON"
    live_cycle_runner_click_named_point BASE_TELEPORT_BUTTON || return 2
    # BASE_PRESS_DELAY is only the gap BETWEEN base clicks; the final click pays
    # no trailing delay. The post-burst settle is the wait_key sleep below.
    if test "$i" -lt "$base_count"; then
      input_sleep "$base_press_delay" || return 2
    fi
  done

  local _wait_value
  if test "${__lcr_prepared:-0}" = "1" && test "$wait_key" = "POST_BASE_WAIT"; then
    _wait_value="$__lcr_post_base_wait"
  else
    _wait_value="$(live_cycle_runner_get_timing "$wait_key")" || return 2
  fi
  if test "${MACRO_TRACE_TIMING:-}" = "1" && test "$label" = "base_teleport"; then
    __lcr_transition_start_ms="$(live_cycle_runner_now_ms)"
    live_cycle_runner_trace "transition base_to_menu final_base_click_done_ms=${__lcr_transition_start_ms}"
    live_cycle_runner_trace "transition base_to_menu post_base_wait_start key=${wait_key} duration=${_wait_value}"
  fi
  input_sleep "$_wait_value" || return 2
  if test "${MACRO_TRACE_TIMING:-}" = "1" && test "$label" = "base_teleport"; then
    live_cycle_runner_trace "transition base_to_menu post_base_wait_done_ms=$(live_cycle_runner_now_ms)"
  fi
}

live_cycle_runner_run_cycle() {
  local cycle="$1"
  local with_potions="$2"
  local return_to_base_after_cycle="$3"
  local _phase_start_ms _phase_end_ms _phase_dur_ms _cycle_start_ms _cycle_end_ms
  local _post_place_wait

  __lcr_timing_cycle="$cycle"

  live_cycle_runner_trace "cycle=${cycle} begin"

  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    if test -n "${__lcr_prev_cycle_end_ms:-}" && test "$cycle" -gt 1; then
      _cycle_start_ms="$(live_cycle_runner_now_ms)"
      live_cycle_runner_trace "timing between_cycles previous_cycle=$((cycle - 1)) next_cycle=${cycle} duration_ms=$((_cycle_start_ms - __lcr_prev_cycle_end_ms))"
    else
      _cycle_start_ms="$(live_cycle_runner_now_ms)"
    fi
    _phase_start_ms="$_cycle_start_ms"
    live_cycle_runner_trace "timing cycle=${cycle} phase=base start_ms=${_phase_start_ms}"
  fi

  live_cycle_runner_trace "cycle=${cycle} phase=base"
  live_cycle_runner_teleport_to_base "$cycle" base_teleport POST_BASE_WAIT || return 2

  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    _phase_end_ms="$(live_cycle_runner_now_ms)"
    _phase_dur_ms=$((_phase_end_ms - _phase_start_ms))
    live_cycle_runner_trace "timing cycle=${cycle} phase=base end_ms=${_phase_end_ms} duration_ms=${_phase_dur_ms}"
    _phase_start_ms="$_phase_end_ms"
    live_cycle_runner_trace "timing cycle=${cycle} phase=potion start_ms=${_phase_start_ms}"
  fi

  # Potions run from the base UI state, before movement begins. The on-screen
  # UI must stay in its base state for the inventory/potion menu navigation to
  # land on the right targets and the potions to apply.
  if test "$with_potions" = "1"; then
    live_cycle_runner_trace "cycle=${cycle} phase=potion runner=potion_runner"
    potion_runner_run || return 2
  else
    live_cycle_runner_trace "cycle=${cycle} phase=potion skipped"
  fi

  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    _phase_end_ms="$(live_cycle_runner_now_ms)"
    _phase_dur_ms=$((_phase_end_ms - _phase_start_ms))
    live_cycle_runner_trace "timing cycle=${cycle} phase=potion end_ms=${_phase_end_ms} duration_ms=${_phase_dur_ms}"
    _phase_start_ms="$_phase_end_ms"
    live_cycle_runner_trace "timing cycle=${cycle} phase=placement start_ms=${_phase_start_ms}"
  fi

  # One continuous click worker spans the entire forward+left L-shape, so
  # clicking never pauses at the forward->left transition. There is no separate
  # pack-selection click: the single move to PACK_CLICK_POINT happens inside the
  # placement path, which then spam-clicks it across both movement segments.
  live_cycle_runner_trace "cycle=${cycle} phase=placement mode=continuous-click-l-shape"
  live_cycle_runner_run_continuous_l_shape_placement || return 2

  release_all_inputs || return 2
  if test "${__lcr_prepared:-0}" = "1"; then
    _post_place_wait="$__lcr_post_place_wait"
  else
    _post_place_wait="$(live_cycle_runner_get_timing POST_PLACE_WAIT)" || return 2
  fi
  input_sleep "$_post_place_wait" || return 2

  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    _phase_end_ms="$(live_cycle_runner_now_ms)"
    _phase_dur_ms=$((_phase_end_ms - _phase_start_ms))
    live_cycle_runner_trace "timing cycle=${cycle} phase=placement end_ms=${_phase_end_ms} duration_ms=${_phase_dur_ms}"
  fi

  if test "$return_to_base_after_cycle" = "1"; then
    live_cycle_runner_trace "cycle=${cycle} phase=return_to_base"
    live_cycle_runner_teleport_to_base "$cycle" return_to_base POST_SECOND_BASE_WAIT || return 2
  fi

  live_cycle_runner_trace "cycle=${cycle} complete"
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    _cycle_end_ms="$(live_cycle_runner_now_ms)"
    __lcr_prev_cycle_end_ms="$_cycle_end_ms"
    live_cycle_runner_trace "timing cycle=${cycle} phase=cycle_total start_ms=${_cycle_start_ms} end_ms=${_cycle_end_ms} duration_ms=$((_cycle_end_ms - _cycle_start_ms))"
  fi
}

live_cycle_runner_run() {
  local cycles="${1:-$LIVE_CYCLE_RUNNER_DEFAULT_CYCLES}"
  local with_potions="${2:-$LIVE_CYCLE_RUNNER_DEFAULT_POTIONS}"
  local return_to_base_after_cycle="${3:-0}"
  local until_stopped="${4:-0}"
  local dry_run_limit="${5:-0}"
  local mode
  local cycle
  local status

  mode="$(input_mode)" || return 2
  if test "$mode" = "live"; then
    live_cycle_runner_require_live_gate || return 2
  fi

  if test "$until_stopped" = "1"; then
    # Until-stopped is NOT a finite --cycles N run, so the numeric max-cycle cap
    # does not apply. To keep dry-run validation bounded (never infinite), a
    # positive --dry-run-limit is required when not running live.
    if test "$mode" != "live" && test "$dry_run_limit" -lt 1; then
      printf 'ERROR: --until-stopped in dry-run requires --dry-run-limit N (bounded validation)\n' >&2
      return 2
    fi
  else
    cycles="$(live_cycle_runner_parse_cycles "$cycles")" || return 2
  fi

  live_cycle_runner_load_context || return $?
  live_cycle_runner_preflight || return $?

  # Install the emergency cleanup net only once the live gate has passed.
  if test "$mode" = "live"; then
    trap 'live_cycle_runner_emergency_cleanup' EXIT
  fi

  release_all_inputs || return 2

  if test "$with_potions" = "1"; then
    potion_runner_prepare_for_cycle_loop || return $?
  fi

  live_cycle_runner_prepare_context || return $?

  if test "$until_stopped" = "1"; then
    # One continuous single-process loop: run one complete cycle per iteration,
    # forever, until Ctrl+C (SIGINT terminates the process and the EXIT trap
    # cleans up) or a cycle fails. There is NO artificial sleep between cycles;
    # the next cycle naturally begins with its own base phase.
    live_cycle_runner_trace "start mode=until-stopped potions=${with_potions} concurrent=1 return_to_base_after_cycle=${return_to_base_after_cycle} dry_run_limit=${dry_run_limit}"
    cycle=1
    while true; do
      live_cycle_runner_run_cycle "$cycle" "$with_potions" "$return_to_base_after_cycle" || return $?
      # Bounded dry-run validation only: cap the loop so the until-stopped path
      # is provable without looping forever. Never applied in live mode.
      if test "$mode" != "live" && test "$dry_run_limit" -gt 0 && test "$cycle" -ge "$dry_run_limit"; then
        break
      fi
      cycle=$((cycle + 1))
    done

    release_all_inputs || return 2
    live_cycle_runner_trace "complete mode=until-stopped cycles=${cycle}"
    return 0
  fi

  live_cycle_runner_trace "start cycles=${cycles} potions=${with_potions} concurrent=1 return_to_base_after_cycle=${return_to_base_after_cycle}"

  for ((cycle = 1; cycle <= cycles; cycle++)); do
    live_cycle_runner_run_cycle "$cycle" "$with_potions" "$return_to_base_after_cycle" || return 2
  done

  release_all_inputs || return 2
  live_cycle_runner_trace "complete cycles=${cycles}"
}

live_cycle_runner_usage() {
  printf 'Usage: %s --dry-run [--cycles N | --until-stopped --dry-run-limit N] [--with-potions] [--no-potions] [--return-to-base-after-cycle]\n' "$0" >&2
  printf '       %s --live [--cycles N | --until-stopped] [--with-potions] [--no-potions] [--return-to-base-after-cycle]\n' "$0" >&2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail

  mode=""
  case "${1:-}" in
    --dry-run)
      mode="dry-run"
      shift
      ;;
    --live)
      mode="live"
      shift
      ;;
    *)
      live_cycle_runner_usage
      exit 2
      ;;
  esac

  cycles="$LIVE_CYCLE_RUNNER_DEFAULT_CYCLES"
  with_potions="$LIVE_CYCLE_RUNNER_DEFAULT_POTIONS"
  return_to_base_after_cycle=0
  until_stopped=0
  dry_run_limit=0

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
      --until-stopped)
        until_stopped=1
        shift
        ;;
      --dry-run-limit)
        shift
        if test "$#" -eq 0; then
          printf 'ERROR: --dry-run-limit requires a value\n' >&2
          exit 2
        fi
        if ! [[ "$1" =~ ^[0-9]+$ ]] || test "$1" -lt 1; then
          printf 'ERROR: --dry-run-limit must be a positive integer: %s\n' "$1" >&2
          exit 2
        fi
        dry_run_limit="$1"
        shift
        ;;
      --with-potions)
        with_potions=1
        shift
        ;;
      --no-potions)
        with_potions=0
        shift
        ;;
      --return-to-base-after-cycle)
        return_to_base_after_cycle=1
        shift
        ;;
      *)
        live_cycle_runner_usage
        exit 2
        ;;
    esac
  done

  if test "$mode" = "live"; then
    live_cycle_runner_require_live_gate
  fi

  export MACRO_INPUT_MODE="$mode"
  live_cycle_runner_run "$cycles" "$with_potions" "$return_to_base_after_cycle" "$until_stopped" "$dry_run_limit"
fi
