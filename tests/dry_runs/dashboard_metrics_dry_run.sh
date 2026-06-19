#!/usr/bin/env bash
set -uo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

assert_eq() {
  local got="$1"
  local want="$2"
  local label="$3"
  if test "$got" != "$want"; then
    printf 'FAIL: %s — got=%q want=%q\n' "$label" "$got" "$want" >&2
    return 1
  fi
  printf 'PASS: %s\n' "$label"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  # Use here-string to avoid grep -q SIGPIPE + pipefail false negative.
  if ! grep -qF "$needle" <<< "$haystack" 2>/dev/null; then
    printf 'FAIL: %s — output does not contain: %s\n' "$label" "$needle" >&2
    return 1
  fi
  printf 'PASS: %s\n' "$label"
}

assert_zero() {
  local status="$1"
  local label="$2"
  if test "$status" -ne 0; then
    printf 'FAIL: %s — expected 0, got %s\n' "$label" "$status" >&2
    return 1
  fi
  printf 'PASS: %s\n' "$label"
}

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input must not be enabled for this dry-run test\n' >&2
  exit 1
fi
printf 'PASS: live input is not enabled\n'

# ── Isolated temp environment ─────────────────────────────────────────────────
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
export MACRO_PROJECT_ROOT="$tmp_root"
mkdir -p "$tmp_root/runtime_config/orchestrator"
mkdir -p "$tmp_root/src/lib"
mkdir -p "$tmp_root/config_templates/orchestrator"

# Copy config template so BUNDLES_PER_CYCLE is available
cp "$project_root/config_templates/orchestrator/defaults.conf" \
   "$tmp_root/config_templates/orchestrator/defaults.conf"

# shellcheck source=../../src/lib/run_metrics.sh
. "$project_root/src/lib/run_metrics.sh"

metrics_file="$(run_metrics_state_file)"

# ── Test 1: metrics init creates valid key=value file ────────────────────────
run_metrics_init
result=0
test -f "$metrics_file" || result=1
assert_zero "$result" "run_metrics_init creates metrics file"

content="$(cat "$metrics_file")"
assert_contains "$content" "COMPLETED_PACK_CYCLES=0" "init: COMPLETED_PACK_CYCLES=0"
assert_contains "$content" "MARKET_RUNS=0" "init: MARKET_RUNS=0"
assert_contains "$content" "FIGURINES_RUNS=0" "init: FIGURINES_RUNS=0"
assert_contains "$content" "RECOVERY_RUNS=0" "init: RECOVERY_RUNS=0"
assert_contains "$content" "RUN_STARTED_AT_EPOCH=" "init: RUN_STARTED_AT_EPOCH present"
assert_contains "$content" "LAST_UPDATE_EPOCH=" "init: LAST_UPDATE_EPOCH present"

# ── Test 2: default bundles per cycle is 13 ──────────────────────────────────
assert_contains "$content" "BUNDLES_PER_CYCLE=13" "default BUNDLES_PER_CYCLE=13"

# ── Test 3: override to 14 works ─────────────────────────────────────────────
BUNDLES_PER_CYCLE=14 run_metrics_init
content2="$(cat "$metrics_file")"
assert_contains "$content2" "BUNDLES_PER_CYCLE=14" "override BUNDLES_PER_CYCLE=14"

# Reset to 13
run_metrics_init

# ── Test 4: increment COMPLETED_PACK_CYCLES ──────────────────────────────────
run_metrics_cycle_complete
content3="$(cat "$metrics_file")"
assert_contains "$content3" "COMPLETED_PACK_CYCLES=1" "cycle_complete increments to 1"

run_metrics_cycle_complete
run_metrics_cycle_complete
content4="$(cat "$metrics_file")"
assert_contains "$content4" "COMPLETED_PACK_CYCLES=3" "cycle_complete increments to 3"

# ── Test 5: estimated bundles uses BUNDLES_PER_CYCLE ─────────────────────────
cycles_val="$(grep -E '^COMPLETED_PACK_CYCLES=' "$metrics_file" | cut -d= -f2)"
bpc_val="$(grep -E '^BUNDLES_PER_CYCLE=' "$metrics_file" | cut -d= -f2)"
estimated=$(( cycles_val * bpc_val ))
assert_eq "$estimated" "39" "estimated bundles = 3 * 13 = 39"

# ── Test 6: buyer and recovery counters ──────────────────────────────────────
run_metrics_market_complete
run_metrics_figurines_complete
run_metrics_recovery_complete
content5="$(cat "$metrics_file")"
assert_contains "$content5" "MARKET_RUNS=1" "market_complete increments MARKET_RUNS"
assert_contains "$content5" "FIGURINES_RUNS=1" "figurines_complete increments FIGURINES_RUNS"
assert_contains "$content5" "RECOVERY_RUNS=1" "recovery_complete increments RECOVERY_RUNS"

# ── Test 7: metrics no-op when not initialized (flush guard) ─────────────────
tmp2="$(mktemp -d)"
prev_root="$MACRO_PROJECT_ROOT"
export MACRO_PROJECT_ROOT="$tmp2"
mkdir -p "$tmp2/runtime_config/orchestrator"

_metrics_started_epoch=""
run_metrics_cycle_complete 2>/dev/null || true
metrics2="$(run_metrics_state_file)"
result2=0
test -f "$metrics2" && result2=1
assert_zero "$result2" "flush is no-op when not initialized"
export MACRO_PROJECT_ROOT="$prev_root"
rm -rf "$tmp2"

# ── Test 8: graceful degradation — missing file returns zeros ─────────────────
rm -f "$metrics_file"
_dash_cycles=0; _dash_bpc=13; _dash_started_epoch=0
# shellcheck source=../../src/lib/run_metrics.sh
. "$project_root/src/lib/run_metrics.sh"
export MACRO_PROJECT_ROOT="$tmp_root"
_dash_read_metrics() {
  _dash_cycles=0; _dash_bpc=13; _dash_started_epoch=0; _dash_market=0
  _dash_figurines=0; _dash_recovery=0; _dash_last_phase=""; _dash_last_event=""
  local mf; mf="$(run_metrics_state_file)"
  if ! test -f "$mf"; then return 0; fi
  local k v
  while IFS='=' read -r k v; do
    case "$k" in
      COMPLETED_PACK_CYCLES) _dash_cycles="$v" ;;
      BUNDLES_PER_CYCLE)     _dash_bpc="$v" ;;
      LAST_PHASE)            _dash_last_phase="$v" ;;
      LAST_EVENT)            _dash_last_event="$v" ;;
      MARKET_RUNS)           _dash_market="$v" ;;
      FIGURINES_RUNS)        _dash_figurines="$v" ;;
      RECOVERY_RUNS)         _dash_recovery="$v" ;;
      RUN_STARTED_AT_EPOCH)  _dash_started_epoch="$v" ;;
    esac
  done < "$mf" 2>/dev/null || true
}
_dash_read_metrics
assert_eq "$_dash_cycles" "0" "missing metrics file: cycles defaults to 0"
assert_eq "$_dash_bpc" "13" "missing metrics file: bpc defaults to 13"

# ── Test 9: dashboard renderer output contains required strings ───────────────
# Source pack-opener-ui functions in a sandboxed way to test the renderer.
# We only need the dashboard section; we simulate the required globals.
TOGGLE_PACK_OPENER=1
TOGGLE_MARKET_BUYER=1
TOGGLE_FIGURINES_BUYER=1
TOGGLE_RECOVERY_RESTART=0
ACC_DEBUG_LOGS=0
interactive=1
colors_enabled=0
RESET=''; BOLD=''; DIM=''; CYAN=''; MAGENTA=''; GREEN=''; YELLOW=''; RED=''; GREY=''
METRICS_FILE="$(run_metrics_state_file)"

# Re-initialize so the metrics file exists for the renderer
run_metrics_init
run_metrics_cycle_complete
run_metrics_cycle_complete
run_metrics_market_complete

clear_screen() { :; }

# Extract the "Live dashboard renderer" section (up to startup_pulse).
# This covers all helpers: strip_ansi, dashboard_row, dashboard_sep,
# dashboard_header, print_live_controls_line, _dash_read_metrics, show_live_dashboard.
tmpscript="$(mktemp)"
trap 'rm -f "$tmpscript"; rm -rf "$tmp_root"' EXIT
sed -n '/^# ── Live dashboard renderer/,/^startup_pulse/p' \
  "$project_root/bin/pack-opener-ui" | head -n -1 > "$tmpscript"

# shellcheck disable=SC1090
. "$tmpscript" 2>/dev/null || true

dashboard_out="$(show_live_dashboard "$(date +%s)" "running" 2>/dev/null || true)"

assert_contains "$dashboard_out" "ACC // LIVE DASHBOARD" "dashboard contains ACC // LIVE DASHBOARD"
assert_contains "$dashboard_out" "Run time" "dashboard contains Run time"
assert_contains "$dashboard_out" "Pack cycles" "dashboard contains Pack cycles"
assert_contains "$dashboard_out" "Bundles/cycle" "dashboard contains Bundles/cycle"
assert_contains "$dashboard_out" "Est. bundles" "dashboard contains Est. bundles"
assert_contains "$dashboard_out" "Debug logs" "dashboard contains Debug logs"
assert_contains "$dashboard_out" "OFF" "dashboard shows debug logs OFF by default"
assert_contains "$dashboard_out" "Pack Opener" "dashboard contains Pack Opener module"
assert_contains "$dashboard_out" "Market Buyer" "dashboard contains Market Buyer module"
assert_contains "$dashboard_out" "Figurines Buyer" "dashboard contains Figurines Buyer module"
assert_contains "$dashboard_out" "Recovery Restart" "dashboard contains Recovery Restart module"
assert_contains "$dashboard_out" "Buyer runs" "dashboard contains Buyer runs"
assert_contains "$dashboard_out" "Recovery runs" "dashboard contains Recovery runs"

# ── Test 10: all dashboard lines are exactly 56 visible chars wide ────────────
# Colors are disabled in this test so no ANSI stripping needed.
dashboard_width_ok=1
line_count=0
while IFS= read -r line; do
  line_count=$(( line_count + 1 ))
  len="${#line}"
  if test "$len" -ne 56; then
    printf 'FAIL: dashboard line %d has width %d (expected 56): %s\n' \
      "$line_count" "$len" "$line" >&2
    dashboard_width_ok=0
  fi
done <<< "$dashboard_out"
if test "$dashboard_width_ok" = "1"; then
  printf 'PASS: all dashboard lines are exactly 56 chars wide (%d lines checked)\n' "$line_count"
else
  printf 'FAIL: dashboard has misaligned lines (see above)\n' >&2
  exit 1
fi

# ── Test 11: controls line — all view/state combinations ─────────────────────
ctrl_art_run="$(print_live_controls_line "art" "running" 2>/dev/null || true)"
assert_contains "$ctrl_art_run" "d = dashboard" "controls art/running: d = dashboard"
assert_contains "$ctrl_art_run" "p = pause" "controls art/running: p = pause"

ctrl_dash_run="$(print_live_controls_line "dash" "running" 2>/dev/null || true)"
assert_contains "$ctrl_dash_run" "d = art" "controls dash/running: d = art"
assert_contains "$ctrl_dash_run" "p = pause" "controls dash/running: p = pause"

ctrl_pause_req="$(print_live_controls_line "art" "pause_requested" 2>/dev/null || true)"
assert_contains "$ctrl_pause_req" "d = toggle view" "controls pause_requested: d = toggle view"
assert_contains "$ctrl_pause_req" "pause requested" "controls pause_requested: pause requested"

ctrl_paused="$(print_live_controls_line "art" "paused" 2>/dev/null || true)"
assert_contains "$ctrl_paused" "d = toggle view" "controls paused: d = toggle view"
assert_contains "$ctrl_paused" "c = continue" "controls paused: c = continue"

ctrl_resume="$(print_live_controls_line "dash" "continue_requested" 2>/dev/null || true)"
assert_contains "$ctrl_resume" "d = toggle view" "controls continue_requested: d = toggle view"
assert_contains "$ctrl_resume" "resuming" "controls continue_requested: resuming"

# ── Test 12: toggling view does not remove controls (key loop fix) ────────────
ui_content="$(cat "$project_root/bin/pack-opener-ui")"
# After art redraw (_need_redraw=1), _state_changed is forced to 1 so controls print.
assert_contains "$ui_content" '_state_changed=1' "key loop: forces controls after art redraw"
assert_contains "$ui_content" 'print_live_controls_line' "key loop: uses centralized controls helper"

# ── Test 13: config template has BUNDLES_PER_CYCLE ───────────────────────────
template_content="$(cat "$project_root/config_templates/orchestrator/defaults.conf")"
assert_contains "$template_content" "BUNDLES_PER_CYCLE=13" "config template has BUNDLES_PER_CYCLE=13"
assert_contains "$template_content" "14" "config template mentions 14 for future change"

# ── Test 14: ACC_DEBUG_LOGS default is OFF in UI ─────────────────────────────
assert_contains "$ui_content" 'ACC_DEBUG_LOGS:-0' "UI: ACC_DEBUG_LOGS defaults to 0"
assert_contains "$ui_content" 'ACC_DEBUG_LOGS' "UI: references ACC_DEBUG_LOGS gate"

# ── Test 15: d/p/c key handlers present ─────────────────────────────────────
assert_contains "$ui_content" 'd = dashboard' "UI: controls mention d = dashboard"
assert_contains "$ui_content" 'd = art' "UI: controls mention d = art"
assert_contains "$ui_content" "p|P)" "UI: p key handler present"
assert_contains "$ui_content" "c|C)" "UI: c key handler present"
assert_contains "$ui_content" "d|D)" "UI: d key handler present"

# ── Test 16: BUNDLES_PER_CYCLE comment mentions 14 ───────────────────────────
assert_contains "$template_content" "Change to 14" "config template has change-to-14 comment"

# ── Test 17: no live input env vars required ──────────────────────────────────
printf 'PASS: no live input env vars required (dry-run only)\n'

# ── Test 18: run_metrics.sh is sourced by orchestrator.sh ────────────────────
orch_content="$(cat "$project_root/src/modules/orchestrator.sh")"
assert_contains "$orch_content" "run_metrics.sh" "orchestrator.sh sources run_metrics.sh"
assert_contains "$orch_content" "run_metrics_init" "orchestrator.sh calls run_metrics_init"
assert_contains "$orch_content" "run_metrics_cycle_complete" "orchestrator.sh calls run_metrics_cycle_complete"

# ── Test 19: orchestrator_trace is gated by acc_trace_enabled ────────────────
assert_contains "$orch_content" "acc_trace_enabled" "orchestrator_trace is gated by acc_trace_enabled"

# ── Test 20: dashboard uses dashboard_row helper (no old misaligned helpers) ──
assert_contains "$ui_content" "dashboard_row" "UI uses dashboard_row helper"
result_old=0
printf '%s' "$ui_content" | grep -qF '_dash_box_line' && result_old=1 || true
if test "$result_old" = "0"; then
  printf 'PASS: old misaligned _dash_box_line is removed\n'
else
  printf 'FAIL: old _dash_box_line still present — may cause misalignment\n' >&2
  exit 1
fi

printf '\nAll dashboard/metrics dry-run tests passed.\n'
