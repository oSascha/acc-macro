#!/usr/bin/env bash
# Lightweight run-metrics helper for the Full Macro dashboard.
# State is kept in shell globals (within the orchestrator process) and flushed
# to a small file after each completed cycle or module run — never inside click
# bursts, hot input loops, or sleep phases.
#
# State file: runtime_config/orchestrator/run_metrics.conf

_run_metrics_lib_dir="${BASH_SOURCE[0]%/*}"
if test "$_run_metrics_lib_dir" = "${BASH_SOURCE[0]}"; then
  _run_metrics_lib_dir="."
fi

# In-process state (orchestrator process only)
_metrics_started_epoch=""
_metrics_completed_cycles=0
_metrics_bundles_per_cycle=13
_metrics_last_phase=""
_metrics_last_event=""
_metrics_market_runs=0
_metrics_figurines_runs=0
_metrics_recovery_runs=0
_metrics_last_event_vote=""
_metrics_votes_today=0

run_metrics_state_file() {
  local root="${MACRO_PROJECT_ROOT:-}"
  if test -z "$root"; then
    root="$(cd "$_run_metrics_lib_dir/../.." && pwd -P)"
  fi
  printf '%s/runtime_config/orchestrator/run_metrics.conf\n' "$root"
}

run_metrics_flush() {
  if test -z "${_metrics_started_epoch:-}"; then
    return 0
  fi
  local file epoch
  file="$(run_metrics_state_file)"
  mkdir -p "${file%/*}"
  epoch="$(date +%s)"
  {
    printf 'RUN_STARTED_AT_EPOCH=%s\n' "$_metrics_started_epoch"
    printf 'COMPLETED_PACK_CYCLES=%s\n' "$_metrics_completed_cycles"
    printf 'BUNDLES_PER_CYCLE=%s\n' "$_metrics_bundles_per_cycle"
    printf 'LAST_PHASE=%s\n' "$_metrics_last_phase"
    printf 'LAST_EVENT=%s\n' "$_metrics_last_event"
    printf 'LAST_UPDATE_EPOCH=%s\n' "$epoch"
    printf 'MARKET_RUNS=%s\n' "$_metrics_market_runs"
    printf 'FIGURINES_RUNS=%s\n' "$_metrics_figurines_runs"
    printf 'RECOVERY_RUNS=%s\n' "$_metrics_recovery_runs"
    printf 'EVENT_VOTER_ENABLED=%s\n' "${EVENT_VOTER_ENABLED:-0}"
    printf 'LAST_EVENT_VOTE=%s\n' "${_metrics_last_event_vote:-}"
    printf 'EVENT_VOTES_TODAY=%s\n' "${_metrics_votes_today:-0}"
  } > "$file"
}

# Initialize metrics state and write the initial file.
# Call once at the start of a live Full Macro run, after config is loaded.
run_metrics_init() {
  _metrics_started_epoch="$(date +%s)"
  _metrics_completed_cycles=0
  _metrics_bundles_per_cycle="${BUNDLES_PER_CYCLE:-13}"
  _metrics_last_phase="starting"
  _metrics_last_event="init"
  _metrics_market_runs=0
  _metrics_figurines_runs=0
  _metrics_recovery_runs=0
  _metrics_last_event_vote=""
  _metrics_votes_today=0
  run_metrics_flush
}

# Call after each successful pack opener cycle completes.
run_metrics_cycle_complete() {
  _metrics_completed_cycles=$(( _metrics_completed_cycles + 1 ))
  _metrics_last_phase="pack_cycle"
  _metrics_last_event="cycle_complete"
  run_metrics_flush
}

# Call after market buyer run completes (success or failure).
run_metrics_market_complete() {
  _metrics_market_runs=$(( _metrics_market_runs + 1 ))
  _metrics_last_phase="market_buyer"
  _metrics_last_event="market_complete"
  run_metrics_flush
}

# Call after figurines buyer run completes (success or failure).
run_metrics_figurines_complete() {
  _metrics_figurines_runs=$(( _metrics_figurines_runs + 1 ))
  _metrics_last_phase="figurines_buyer"
  _metrics_last_event="figurines_complete"
  run_metrics_flush
}

# Call after recovery restart run completes.
run_metrics_recovery_complete() {
  _metrics_recovery_runs=$(( _metrics_recovery_runs + 1 ))
  _metrics_last_phase="recovery"
  _metrics_last_event="recovery_complete"
  run_metrics_flush
}

run_metrics_event_vote_complete() {
  local slot="${1:-none}"
  local label="${2:-unknown}"
  _metrics_last_event_vote="$(date +%H:%M) $slot/$label"
  _metrics_votes_today=$(( _metrics_votes_today + 1 ))
  _metrics_last_phase="event_voter"
  _metrics_last_event="vote_${slot}"
  run_metrics_flush
}

# Update the last phase label without flushing immediately.
# Use at safe boundaries where a flush will follow shortly.
run_metrics_set_phase() {
  _metrics_last_phase="${1:-}"
  _metrics_last_event="${2:-}"
}
