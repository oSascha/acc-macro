#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

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

run_dry() {
  MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" \
    "$project_root/src/modules/live_cycle_runner.sh" --dry-run "$@" 2>&1
}

run_dry_trace() {
  MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" MACRO_TRACE_TIMING=1 \
    "$project_root/src/modules/live_cycle_runner.sh" --dry-run "$@" 2>&1
}

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input allowance must not be enabled for this dry-run test\n' >&2
  exit 1
fi
printf 'PASS: live input allowance is not enabled\n'

# --cycles 1 works; potions run by default (no flag).
output_1="$(run_dry --cycles 1)"
assert_contains "$output_1" "TRACE live-cycle-runner start cycles=1 potions=1 concurrent=1" "cycles 1 start"
assert_contains "$output_1" "TRACE live-cycle-runner cycle=1 begin" "cycles 1 cycle begin"
assert_contains "$output_1" "TRACE live-cycle-runner complete cycles=1" "cycles 1 complete"
assert_contains "$output_1" "OK: live cycle runner timing BASE_PRESS_COUNT_NORMAL = 3" "base click count config"
assert_contains "$output_1" "OK: live cycle runner timing BASE_PRESS_DELAY = 5ms (5ms)" "base click delay config"
assert_contains "$output_1" "TRACE live-cycle-runner cycle=1 base_teleport count=3" "cycle 1 base click recovery count"
assert_contains "$output_1" "TRACE live-cycle-runner cycle=1 base_teleport click_index=1/3 point=BASE_TELEPORT_BUTTON" "cycle 1 base click 1"
assert_contains "$output_1" "TRACE live-cycle-runner cycle=1 base_teleport click_index=2/3 point=BASE_TELEPORT_BUTTON" "cycle 1 base click 2"
assert_contains "$output_1" "TRACE live-cycle-runner cycle=1 base_teleport click_index=3/3 point=BASE_TELEPORT_BUTTON" "cycle 1 base click 3"
assert_contains "$output_1" "TRACE input dry-run sleep 5ms" "base click delay trace"

# BASE_PRESS_DELAY (5ms) is the gap BETWEEN base clicks only: a 3-click burst has
# exactly 2 such sleeps and no trailing delay after click #3. POST_BASE_WAIT (the
# 1ms settle) follows the final click and precedes the potion phase.
base_burst_region="$(printf '%s\n' "$output_1" \
  | sed -n '/cycle=1 base_teleport count/,/cycle=1 phase=potion/p')"
base_delay_count="$(printf '%s\n' "$base_burst_region" | grep -c 'TRACE input dry-run sleep 5ms')"
if test "$base_delay_count" -ne 2; then
  printf 'FAIL: expected exactly 2 BASE_PRESS_DELAY sleeps for a 3-click base burst, got %s\n' "$base_delay_count" >&2
  printf '%s\n' "$base_burst_region" >&2
  exit 1
fi
printf 'PASS: 3-click base burst has exactly 2 BASE_PRESS_DELAY sleeps (no trailing delay)\n'
# After the final base click there is no trailing 5ms delay; POST_BASE_WAIT (1ms)
# is the only sleep before the potion phase begins.
post_final_click_region="$(printf '%s\n' "$output_1" \
  | sed -n '/cycle=1 base_teleport click_index=3\/3/,/cycle=1 phase=potion/p')"
assert_not_contains "$post_final_click_region" "TRACE input dry-run sleep 5ms" "no trailing BASE_PRESS_DELAY after final base click"
assert_contains "$post_final_click_region" "TRACE input dry-run sleep 1ms" "POST_BASE_WAIT follows final base click"

# --cycles 2 works; default plan still says potions=1 and concurrent=1.
output_2="$(run_dry --cycles 2)"
assert_contains "$output_2" "TRACE live-cycle-runner start cycles=2 potions=1 concurrent=1" "cycles 2 start"
assert_contains "$output_2" "TRACE live-cycle-runner cycle=2 begin" "cycles 2 cycle 2 begin"
assert_contains "$output_2" "TRACE live-cycle-runner complete cycles=2" "cycles 2 complete"
assert_contains "$output_2" "TRACE live-cycle-runner cycle=1 base_teleport count=3" "cycles 2 cycle 1 base click recovery count"
assert_contains "$output_2" "TRACE live-cycle-runner cycle=2 base_teleport count=3" "cycles 2 cycle 2 base click recovery count"

# Default (no flag) runs the potion runner each cycle.
assert_contains "$output_1" "TRACE live-cycle-runner cycle=1 phase=potion runner=potion_runner" "default runs potion runner"
assert_contains "$output_1" "TRACE potion-runner start" "default invokes potion runner"
assert_contains "$output_1" "TRACE potion-runner pre_menu_wait key=POTION_PRE_MENU_CLICK_WAIT duration=" "potion pre-menu wait"
assert_contains "$output_1" "TRACE potion-runner post_inventory_open_wait key=POST_INVENTORY_OPEN_WAIT duration=" "potion post inventory wait"
assert_not_contains "$output_1" "phase=potion skipped" "default never skips potions"

# --no-potions traces potion skipped and never runs the potion runner.
output_np="$(run_dry --cycles 1 --no-potions)"
assert_contains "$output_np" "TRACE live-cycle-runner start cycles=1 potions=0 concurrent=1" "no-potions start flag"
assert_contains "$output_np" "TRACE live-cycle-runner cycle=1 phase=potion skipped" "no-potions skip trace"
assert_not_contains "$output_np" "phase=potion runner=potion_runner" "no-potions never runs runner"
assert_not_contains "$output_np" "TRACE potion-runner start" "no-potions never starts potion runner"

# --with-potions remains an explicit synonym for the default.
output_wp="$(run_dry --cycles 2 --with-potions)"
assert_contains "$output_wp" "TRACE live-cycle-runner start cycles=2 potions=1 concurrent=1" "with-potions start flag"
assert_contains "$output_wp" "TRACE live-cycle-runner cycle=1 phase=potion runner=potion_runner" "with-potions cycle 1 boundary"
assert_contains "$output_wp" "TRACE live-cycle-runner cycle=2 phase=potion runner=potion_runner" "with-potions cycle 2 boundary"

# The old trailing base teleport is explicit opt-in only.
output_return_base="$(run_dry --cycles 1 --return-to-base-after-cycle)"
assert_contains "$output_return_base" "TRACE live-cycle-runner start cycles=1 potions=1 concurrent=1 return_to_base_after_cycle=1" "return-to-base opt-in start flag"
assert_contains "$output_return_base" "TRACE live-cycle-runner cycle=1 phase=return_to_base" "return-to-base opt-in phase"

# PACK_CLICK_POINT is the active target; PLACE_HOLD_POINT is not. There is no
# standalone pack-selection click; the placement path moves to PACK_CLICK_POINT
# once and the single continuous click worker spams it at the current position.
assert_contains "$output_1" "TRACE live-cycle-runner move point=PACK_CLICK_POINT x=88 y=563" "pack move active target"
assert_contains "$output_1" "point=PACK_CLICK_POINT click_mode=current-position" "worker uses PACK_CLICK_POINT"
assert_not_contains "$output_1" "point=PLACE_HOLD_POINT" "no active PLACE_HOLD_POINT target"

# Placement is a single continuous-click L-shape phase; the old per-segment
# concurrent-click-e forward/left phases are gone.
assert_contains "$output_1" "TRACE live-cycle-runner cycle=1 phase=placement mode=continuous-click-l-shape" "placement phase continuous"
assert_not_contains "$output_1" "phase=forward mode=concurrent-click-e" "no forward concurrent phase"
assert_not_contains "$output_1" "phase=left mode=concurrent-click-e" "no left concurrent phase"
assert_not_contains "$output_1" "phase=select_pack" "no select_pack phase"

# Exactly ONE click worker start spans the whole L-shape, scoped continuous.
click_start_count="$(printf '%s\n' "$output_1" | grep -c 'placement worker=click start')"
if test "$click_start_count" -ne 1; then
  printf 'FAIL: expected exactly one click worker start, got %s\n' "$click_start_count" >&2
  printf '%s\n' "$output_1" >&2
  exit 1
fi
printf 'PASS: exactly one continuous click worker start\n'
assert_contains "$output_1" "click_worker_scope=continuous_l_shape" "click worker scoped continuous L-shape"

# Both movement segments still happen inside the one placement phase.
assert_contains "$output_1" "TRACE live-cycle-runner movement segment=forward key=w duration_ms=" "forward movement segment"
assert_contains "$output_1" "TRACE live-cycle-runner movement segment=left key=a duration_ms=" "left movement segment"

# Click worker simulated trace exists (dry-run spawns no background worker), and
# the underlying bounded burst primitive is exercised.
assert_contains "$output_1" "TRACE live-cycle-runner placement worker=click simulated=1" "placement click worker simulated"
assert_contains "$output_1" "TRACE input dry-run click_current_burst count=" "underlying click burst primitive"

# The continuous worker starts before forward, survives the forward->left
# transition, and stops only after left: prove via marker ordering.
worker_seq="$(printf '%s\n' "$output_1" \
  | grep -oE 'placement worker=click start|movement segment=forward|movement segment=left|placement worker=click stop' \
  | tr '\n' ',')"
expected_seq="placement worker=click start,movement segment=forward,movement segment=left,placement worker=click stop,"
if test "$worker_seq" != "$expected_seq"; then
  printf 'FAIL: continuous click worker did not span forward->left without a stop\n' >&2
  printf 'expected: %s\n' "$expected_seq" >&2
  printf 'actual:   %s\n' "$worker_seq" >&2
  exit 1
fi
printf 'PASS: click worker spans forward->left continuously, stops only after left\n'

# E is handled inside the placement path (per runtime PLACE_LIVE_E_ENABLED), not
# as a per-segment worker that could stop clicking between forward and left.
assert_contains "$output_1" "TRACE live-cycle-runner placement worker=e" "E handled within placement path"
if [[ "$output_1" == *"placement worker=e start"* ]]; then
  assert_contains "$output_1" "TRACE input dry-run key_tap_burst key=e count=" "underlying E tap primitive (E enabled)"
  printf 'PASS: E enabled -> one continuous E worker inside placement\n'
else
  assert_contains "$output_1" "placement worker=e simulated=0 enabled=0" "E disabled trace"
  printf 'PASS: E disabled -> placement is pure continuous clicking\n'
fi

# no live input allowance is used / no live-only traces leak into dry-run
assert_not_contains "$output_1" "MACRO_LIVE_INPUT_ALLOWED=1" "dry-run output free of live allowance"
assert_not_contains "$output_1" "segment_worker_killed" "dry-run free of worker kill trace"
assert_not_contains "$output_1" "click_pid=" "dry-run free of live worker pids"

mousemove_sync_text="mousemove ""--sync"
assert_not_contains "$output_1" "$mousemove_sync_text" "blocking sync move absent"

# phase order: base, potion, placement (cycle 1)
# Potions must run from the base UI state before movement begins. There is no
# separate pack-selection click; the placement phase spams PACK_CLICK_POINT.
phase_order="$(printf '%s\n' "$output_1" \
  | sed -n 's/^TRACE live-cycle-runner cycle=1 phase=\([a-z_]*\).*/\1/p' \
  | tr '\n' ' ')"
expected_order="base potion placement "
if test "$phase_order" != "$expected_order"; then
  printf 'FAIL: cycle 1 phase order mismatch\n' >&2
  printf 'expected: %s\n' "$expected_order" >&2
  printf 'actual:   %s\n' "$phase_order" >&2
  exit 1
fi
printf 'PASS: cycle 1 phase order is base, potion, placement\n'
assert_not_contains "$output_1" "TRACE live-cycle-runner cycle=1 phase=return_to_base" "default has no trailing return_to_base"

phase_order_2="$(printf '%s\n' "$output_2" \
  | sed -n 's/^TRACE live-cycle-runner cycle=\([0-9]\) phase=\([a-z_]*\).*/cycle=\1 phase=\2/p' \
  | tr '\n' ' ')"
expected_order_2="cycle=1 phase=base cycle=1 phase=potion cycle=1 phase=placement cycle=2 phase=base cycle=2 phase=potion cycle=2 phase=placement "
if test "$phase_order_2" != "$expected_order_2"; then
  printf 'FAIL: cycles 2 phase order mismatch\n' >&2
  printf 'expected: %s\n' "$expected_order_2" >&2
  printf 'actual:   %s\n' "$phase_order_2" >&2
  exit 1
fi
printf 'PASS: cycles 2 phase order repeats base, potion, placement without trailing return_to_base\n'

return_phase_order="$(printf '%s\n' "$output_return_base" \
  | sed -n 's/^TRACE live-cycle-runner cycle=1 phase=\([a-z_]*\).*/\1/p' \
  | tr '\n' ' ')"
expected_return_phase_order="base potion placement return_to_base "
if test "$return_phase_order" != "$expected_return_phase_order"; then
  printf 'FAIL: return-to-base opt-in phase order mismatch\n' >&2
  printf 'expected: %s\n' "$expected_return_phase_order" >&2
  printf 'actual:   %s\n' "$return_phase_order" >&2
  exit 1
fi
printf 'PASS: return-to-base opt-in phase order includes trailing return_to_base\n'

# Until-stopped mode: ONE continuous loop of complete cycles in a single process
# with no between-cycle pause. Bounded for validation with --dry-run-limit so the
# dry-run is provable without looping forever.
output_until="$(run_dry --until-stopped --dry-run-limit 3)"
assert_contains "$output_until" "TRACE live-cycle-runner start mode=until-stopped" "until-stopped start trace"
assert_contains "$output_until" "dry_run_limit=3" "until-stopped dry-run limit recorded"
assert_contains "$output_until" "TRACE live-cycle-runner cycle=1 begin" "until-stopped cycle 1 begin"
assert_contains "$output_until" "TRACE live-cycle-runner cycle=2 begin" "until-stopped cycle 2 begin"
assert_contains "$output_until" "TRACE live-cycle-runner cycle=3 begin" "until-stopped cycle 3 begin"
assert_contains "$output_until" "TRACE live-cycle-runner cycle=1 complete" "until-stopped cycle 1 complete"
assert_contains "$output_until" "TRACE live-cycle-runner cycle=2 complete" "until-stopped cycle 2 complete"
assert_contains "$output_until" "TRACE live-cycle-runner cycle=3 complete" "until-stopped cycle 3 complete"
assert_contains "$output_until" "TRACE live-cycle-runner complete mode=until-stopped cycles=3" "until-stopped complete trace"

# The until-stopped path has no batch/batch-pause concept anywhere in the trace.
assert_not_contains "$output_until" "batch" "until-stopped trace free of batch wording"
assert_not_contains "$output_until" "cycles=3 potions" "until-stopped is not a finite cycles=3 run"

# Each cycle naturally begins with its own base phase, with no artificial sleep
# inserted between one cycle's completion and the next cycle's begin.
between_cycles_region="$(printf '%s\n' "$output_until" \
  | sed -n '/cycle=1 complete/,/cycle=2 begin/p')"
assert_not_contains "$between_cycles_region" "TRACE input dry-run sleep" "no artificial sleep between cycle 1 and cycle 2"
assert_contains "$output_until" "TRACE live-cycle-runner cycle=2 phase=base" "cycle 2 starts with its own base phase"

# Until-stopped repeats complete cycles continuously: prove cycle begins occur
# back-to-back (1, 2, 3) with no ACC-level batch boundary between them.
until_cycle_seq="$(printf '%s\n' "$output_until" \
  | sed -n 's/^TRACE live-cycle-runner cycle=\([0-9]*\) begin$/\1/p' \
  | tr '\n' ',')"
if test "$until_cycle_seq" != "1,2,3,"; then
  printf 'FAIL: until-stopped cycles did not repeat continuously as 1,2,3\n' >&2
  printf 'actual: %s\n' "$until_cycle_seq" >&2
  exit 1
fi
printf 'PASS: until-stopped repeats cycles 1,2,3 continuously with no batch boundary\n'

# Dry-run until-stopped without a limit must NOT loop forever: it is rejected.
if out_unbounded="$(run_dry --until-stopped 2>&1)"; then
  printf 'FAIL: until-stopped dry-run without --dry-run-limit passed (would loop forever)\n' >&2
  printf '%s\n' "$out_unbounded" >&2
  exit 1
fi
assert_contains "$out_unbounded" "--until-stopped in dry-run requires --dry-run-limit" "until-stopped dry-run requires a bound"
printf 'PASS: until-stopped dry-run without a limit is rejected (never infinite)\n'

# Potion runner prepare-once: context loading and preflight happen once before the
# cycle loop, not once per cycle. Validate with a 2-cycle run.
output_2cy="$(run_dry --cycles 2)"
preflight_count="$(printf '%s\n' "$output_2cy" | grep -c 'OK: potion plan POTION_PLAN_ENABLED')"
if test "$preflight_count" -ne 1; then
  printf 'FAIL: preflight spam: expected 1 POTION_PLAN_ENABLED validation, got %s\n' "$preflight_count" >&2
  printf '%s\n' "$output_2cy" >&2
  exit 1
fi
printf 'PASS: POTION_PLAN_ENABLED validation runs once, not once per cycle (cycles=2)\n'
assert_contains "$output_2cy" "TRACE potion-runner prepared" "prepare-once trace emitted once"
# Both cycles still call the potion runner.
assert_contains "$output_2cy" "TRACE live-cycle-runner cycle=1 phase=potion runner=potion_runner" "cycle 1 potion runner called"
assert_contains "$output_2cy" "TRACE live-cycle-runner cycle=2 phase=potion runner=potion_runner" "cycle 2 potion runner called"
# MENU_BUTTON click must still happen on every cycle.
menu_click_count="$(printf '%s\n' "$output_2cy" | grep -c 'TRACE potion-runner click point=MENU_BUTTON')"
if test "$menu_click_count" -ne 2; then
  printf 'FAIL: expected 2 MENU_BUTTON clicks for cycles=2, got %s\n' "$menu_click_count" >&2
  printf '%s\n' "$output_2cy" >&2
  exit 1
fi
printf 'PASS: MENU_BUTTON clicked once per cycle (cycles=2)\n'

# --no-potions path must not emit a prepare trace.
output_np2="$(run_dry --cycles 2 --no-potions)"
assert_not_contains "$output_np2" "TRACE potion-runner prepared" "no-potions never runs prepare"
assert_not_contains "$output_np2" "OK: potion plan POTION_PLAN_ENABLED" "no-potions never runs preflight"

# until-stopped also uses the prepared context: preflight appears once.
output_until2="$(run_dry --until-stopped --dry-run-limit 2)"
preflight_us_count="$(printf '%s\n' "$output_until2" | grep -c 'OK: potion plan POTION_PLAN_ENABLED')"
if test "$preflight_us_count" -ne 1; then
  printf 'FAIL: until-stopped preflight spam: expected 1 POTION_PLAN_ENABLED, got %s\n' "$preflight_us_count" >&2
  printf '%s\n' "$output_until2" >&2
  exit 1
fi
printf 'PASS: until-stopped POTION_PLAN_ENABLED validation runs once (dry_run_limit=2)\n'

# MACRO_TRACE_TIMING=1 activates the base-to-menu transition timing markers.
# This path is the key contract: every label in the gap must appear in order.
output_trace="$(run_dry_trace --cycles 1)"
assert_contains "$output_trace" "TRACE live-cycle-runner transition base_to_menu final_base_click_done_ms=" "trace: final base click done timestamp"
assert_contains "$output_trace" "TRACE live-cycle-runner transition base_to_menu post_base_wait_start key=POST_BASE_WAIT" "trace: post_base_wait start label"
assert_contains "$output_trace" "TRACE live-cycle-runner transition base_to_menu post_base_wait_done_ms=" "trace: post_base_wait done timestamp"
assert_contains "$output_trace" "TRACE potion-runner transition base_to_menu potion_runner_enter_ms=" "trace: potion runner enter timestamp"
assert_contains "$output_trace" "TRACE potion-runner transition base_to_menu release_all_inputs_start_ms=" "trace: release_all_inputs start timestamp"
assert_contains "$output_trace" "TRACE potion-runner transition base_to_menu release_all_inputs_done_ms=" "trace: release_all_inputs done timestamp"
assert_contains "$output_trace" "TRACE potion-runner transition base_to_menu pre_menu_wait_start key=POTION_PRE_MENU_CLICK_WAIT" "trace: pre_menu_wait start label"
assert_contains "$output_trace" "TRACE potion-runner transition base_to_menu pre_menu_wait_done_ms=" "trace: pre_menu_wait done timestamp"
assert_contains "$output_trace" "TRACE potion-runner transition base_to_menu menu_click_start point=MENU_BUTTON ms=" "trace: menu click start timestamp"
assert_contains "$output_trace" "TRACE potion-runner transition base_to_menu total_ms=" "trace: total transition ms"

# Without the flag, no timing traces appear.
assert_not_contains "$output_1" "transition base_to_menu" "no timing trace without MACRO_TRACE_TIMING"

# MACRO_TRACE_TIMING=1 also traces the last-use-to-close transition.
assert_contains "$output_trace" "TRACE potion-runner transition last_use_to_close final_use_click_done_ms=" "trace: last_use_to_close final click done timestamp"
assert_contains "$output_trace" "TRACE potion-runner transition last_use_to_close after_click_interval_start key=POTION_CLICK_INTERVAL" "trace: last_use_to_close click interval start"
assert_contains "$output_trace" "TRACE potion-runner transition last_use_to_close after_click_interval_done_ms=" "trace: last_use_to_close click interval done timestamp"
assert_contains "$output_trace" "TRACE potion-runner transition last_use_to_close disabled_tier_checks_start_ms=" "trace: last_use_to_close disabled tier checks start"
assert_contains "$output_trace" "TRACE potion-runner transition last_use_to_close disabled_tier_checks_done_ms=" "trace: last_use_to_close disabled tier checks done"
assert_contains "$output_trace" "TRACE potion-runner transition last_use_to_close close_click_start point=CLOSE_BUTTON" "trace: last_use_to_close close click start"
assert_contains "$output_trace" "TRACE potion-runner transition last_use_to_close total_ms=" "trace: last_use_to_close total ms"
assert_not_contains "$output_1" "transition last_use_to_close" "no last_use_to_close trace without MACRO_TRACE_TIMING"

printf 'PASS: live-cycle-runner dry run completed\n'
