#!/usr/bin/env bash
# Orchestrator — runs pack opener every cycle with buyer runs at 10-min wall-clock boundaries.
# Buyer order: Market Buyer → Figurines Buyer.
# Slot dedup: tracks last handled slot as YYYYMMDD-HH-MM to prevent double-runs.
# In live mode: sources live_cycle_runner directly so pack cycles run in-process
# (no subprocess fork per cycle, no per-cycle bootstrap/preflight overhead).

_orchestrator_script="${BASH_SOURCE[0]}"
_orchestrator_dir="${_orchestrator_script%/*}"
if test "$_orchestrator_dir" = "$_orchestrator_script"; then
  _orchestrator_dir="."
fi

_orchestrator_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$_orchestrator_project_root"; then
  _orchestrator_project_root="$(cd "$_orchestrator_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$_orchestrator_project_root/src/lib/config.sh"
# shellcheck source=../lib/input.sh
. "$_orchestrator_project_root/src/lib/input.sh"
# shellcheck source=../lib/orchestrator_control.sh
. "$_orchestrator_project_root/src/lib/orchestrator_control.sh"
# shellcheck source=../lib/run_metrics.sh
. "$_orchestrator_project_root/src/lib/run_metrics.sh"
# shellcheck source=market_buyer.sh
. "$_orchestrator_project_root/src/modules/market_buyer.sh"
# shellcheck source=figurines_buyer.sh
. "$_orchestrator_project_root/src/modules/figurines_buyer.sh"
# shellcheck source=star_trials.sh
. "$_orchestrator_project_root/src/modules/star_trials.sh"
# shellcheck source=live_cycle_runner.sh
. "$_orchestrator_project_root/src/modules/live_cycle_runner.sh"
# shellcheck source=recovery_restart.sh
. "$_orchestrator_project_root/src/modules/recovery_restart.sh"
# shellcheck source=event_voter.sh
. "$_orchestrator_project_root/src/modules/event_voter.sh"

# macroctl path — used only for orchestrator_dry_run (not live pack cycles)
_ORCHESTRATOR_MACROCTL="${MACROCTL_PATH:-$_orchestrator_project_root/bin/macroctl}"

# Module toggle env vars (set by UI or caller; override config-file values)
# 1 = enabled, 0 = disabled, empty = fall through to config
ORCHESTRATOR_PACK_ENABLED="${ORCHESTRATOR_PACK_ENABLED:-}"
ORCHESTRATOR_MARKET_BUYER_ENABLED="${ORCHESTRATOR_MARKET_BUYER_ENABLED:-}"
ORCHESTRATOR_FIGURINES_BUYER_ENABLED="${ORCHESTRATOR_FIGURINES_BUYER_ENABLED:-}"
ORCHESTRATOR_RECOVERY_ENABLED="${ORCHESTRATOR_RECOVERY_ENABLED:-}"
ORCHESTRATOR_EVENT_VOTER_ENABLED="${ORCHESTRATOR_EVENT_VOTER_ENABLED:-}"

# Resolved at runtime after loading config
_orch_pack_enabled=1
_orch_market_enabled=1
_orch_figurines_enabled=1
_orch_recovery_enabled=0
_orch_event_voter_enabled=0

orchestrator_trace() {
  if acc_trace_enabled; then
    printf 'TRACE orchestrator %s\n' "$*"
  fi
}

orchestrator_load_config() {
  local runtime_dir defaults_file
  runtime_dir="$(config_orchestrator_dir)"
  defaults_file="$runtime_dir/defaults.conf"

  # Bootstrap from templates if not present
  mkdir -p "$runtime_dir"
  local template_dir
  template_dir="$(config_orchestrator_template_dir)"
  if ! test -f "$defaults_file" && test -f "$template_dir/defaults.conf"; then
    cp "$template_dir/defaults.conf" "$defaults_file"
  fi

  if test -f "$defaults_file"; then
    # shellcheck source=/dev/null
    . "$defaults_file"
  fi

  # Env vars override config-file values (session toggles from UI)
  _orch_pack_enabled="${ORCHESTRATOR_PACK_ENABLED:-${PACK_OPENER_ENABLED:-1}}"
  _orch_market_enabled="${ORCHESTRATOR_MARKET_BUYER_ENABLED:-${MARKET_BUYER_ENABLED:-1}}"
  _orch_figurines_enabled="${ORCHESTRATOR_FIGURINES_BUYER_ENABLED:-${FIGURINES_BUYER_ENABLED:-1}}"

  # Load recovery config to resolve _rec_enabled; env var takes priority for session toggle
  recovery_load_config || true
  _orch_recovery_enabled="${ORCHESTRATOR_RECOVERY_ENABLED:-${_rec_enabled:-0}}"

  event_voter_load_config 2>/dev/null || true
  _orch_event_voter_enabled="${ORCHESTRATOR_EVENT_VOTER_ENABLED:-${EVENT_VOTER_ENABLED:-0}}"
}

# Returns current 10-minute slot as YYYYMMDD-HH-MM if minute % 10 == 0, else empty.
orchestrator_current_slot() {
  local minute
  minute="$(date '+%M')"
  # Strip leading zero so arithmetic works in bash
  local minute_int=$(( 10#$minute ))
  if test $(( minute_int % 10 )) -eq 0; then
    date '+%Y%m%d-%H-%M'
  else
    printf ''
  fi
}

orchestrator_require_live_gate() {
  if test "${MACRO_INPUT_MODE:-dry-run}" != "live"; then
    log_error "orchestrator live mode requires MACRO_INPUT_MODE=live"
    return 2
  fi
  if test "${MACRO_LIVE_INPUT_ALLOWED:-}" != "1"; then
    log_error "orchestrator live mode requires MACRO_LIVE_INPUT_ALLOWED=1"
    return 2
  fi
  if test "${MACRO_LIVE_CYCLE_RUNNER_CONFIRM:-}" != "YES"; then
    log_error "orchestrator live mode requires MACRO_LIVE_CYCLE_RUNNER_CONFIRM=YES"
    return 2
  fi
}

orchestrator_run_buyers() {
  local mode="${1:-live}"

  if test "$_orch_market_enabled" = "1"; then
    orchestrator_trace "running market buyer"
    if test "$mode" = "dry-run"; then
      MACRO_INPUT_MODE=dry-run market_buyer_dry_run || return 2
    else
      market_buyer_run || return 2
      run_metrics_market_complete 2>/dev/null || true
    fi
  else
    orchestrator_trace "market buyer disabled — skip"
  fi

  if test "$_orch_figurines_enabled" = "1"; then
    orchestrator_trace "running figurines buyer"
    if test "$mode" = "dry-run"; then
      MACRO_INPUT_MODE=dry-run figurines_buyer_dry_run || return 2
    else
      figurines_buyer_run || return 2
      run_metrics_figurines_complete 2>/dev/null || true
    fi
  else
    orchestrator_trace "figurines buyer disabled — skip"
  fi
}

# Poll interval for the pause wait loop. Override in tests for speed.
_ORCHESTRATOR_PAUSE_POLL="${_ORCHESTRATOR_PAUSE_POLL:-0.5}"

# Check for a pending pause request at a safe boundary. No-op when running.
# Blocks until continue_requested when paused; never interrupts a module mid-run.
orchestrator_check_pause() {
  local state
  state="$(orchestrator_control_get)"
  if test "$state" != "pause_requested"; then
    return 0
  fi
  orchestrator_trace "paused at safe boundary"
  orchestrator_control_set "paused"
  while true; do
    sleep "$_ORCHESTRATOR_PAUSE_POLL"
    state="$(orchestrator_control_get)"
    if test "$state" = "continue_requested"; then
      orchestrator_control_set "running"
      orchestrator_trace "resumed"
      return 0
    fi
  done
}

orchestrator_check_event_voter() {
  if test "$_orch_event_voter_enabled" != "1"; then
    return 0
  fi
  if ! event_voter_should_hold_now 2>/dev/null; then
    return 0
  fi
  orchestrator_trace "event voter: event approaching — holding at safe boundary"
  while ! event_voter_due_now 2>/dev/null; do
    sleep 1
  done
  orchestrator_trace "event voter: running live window"
  event_voter_run_live_window || orchestrator_trace "event voter: window exited non-zero — continuing"
  local ev_display
  if test "${_ev_last_action:-}" = "clicked"; then
    ev_display="clicked ${_ev_last_label:-unknown}/${_ev_last_slot:-none} @ ${_ev_last_event_slot:-}"
  else
    ev_display="${_ev_last_reason:-no_target} @ ${_ev_last_event_slot:-}"
  fi
  run_metrics_event_vote_complete "$ev_display" 2>/dev/null || true
  return 0
}

orchestrator_run() {
  orchestrator_load_config || return 2
  orchestrator_require_live_gate || return 2
  run_metrics_init 2>/dev/null || true

  if test "$_orch_pack_enabled" != "1" \
     && test "$_orch_market_enabled" != "1" \
     && test "$_orch_figurines_enabled" != "1"; then
    log_error "orchestrator: all modules disabled — nothing to run"
    return 2
  fi

  # Preflight all enabled side macros before entering the long loop.
  # Missing points are caught here — not 10 minutes into the run.
  if test "$_orch_market_enabled" = "1"; then
    if ! market_buyer_preflight; then
      log_error "orchestrator: Market Buyer points not configured — calibrate TOP_MARKET_BUTTON_X/Y and MARKET_BUY_ALL_X/Y, or disable Market Buyer"
      return 2
    fi
  fi
  if test "$_orch_figurines_enabled" = "1"; then
    if ! figurines_buyer_preflight; then
      log_error "orchestrator: Figurines Buyer points not configured — calibrate BASE_TELEPORT_BUTTON_X/Y and FIGURINES_BUY_ALL_X/Y, or disable Figurines Buyer"
      return 2
    fi
  fi
  if test "$_orch_recovery_enabled" = "1"; then
    if ! recovery_preflight; then
      log_error "orchestrator: Recovery Restart is enabled but preflight failed — configure recovery or disable it (RECOVERY_ENABLED=0)"
      return 2
    fi
  fi
  if test "$_orch_event_voter_enabled" = "1"; then
    if ! event_voter_preflight 2>/dev/null; then
      orchestrator_trace "event voter preflight failed — voter disabled for this run"
      _orch_event_voter_enabled=0
    fi
  fi

  # Set up pack opener for in-process running (no subprocess per cycle).
  # load_context + preflight + prepare_context are called once here, not per cycle.
  if test "$_orch_pack_enabled" = "1"; then
    live_cycle_runner_load_context || return 2
    live_cycle_runner_preflight || return 2
    trap 'live_cycle_runner_emergency_cleanup' EXIT
    release_all_inputs || return 2
    potion_runner_prepare_for_cycle_loop || return 2
    live_cycle_runner_prepare_context || return 2
  fi

  # Clear any stale pause state just before entering the main loop.
  orchestrator_control_init

  orchestrator_trace "start (pack=${_orch_pack_enabled} market=${_orch_market_enabled} figurines=${_orch_figurines_enabled})"

  local last_side_slot=""
  local current_slot
  local cycle=0
  local buyer_status

  while true; do
    # Safe boundary: before starting new pack cycle
    orchestrator_check_pause
    orchestrator_check_event_voter || true

    if test "$_orch_pack_enabled" = "1"; then
      cycle=$((cycle + 1))
      live_cycle_runner_run_cycle "$cycle" 1 0 || return 2
      run_metrics_cycle_complete 2>/dev/null || true
      # Safe boundary: after pack cycle completes
      orchestrator_check_pause
      orchestrator_check_event_voter || true
    else
      orchestrator_trace "pack opener disabled — idle 2s"
      sleep 2
    fi

    # Slot check runs AFTER each pack cycle (or idle), not before.
    # This ensures buyers never interrupt a cycle mid-run.
    current_slot="$(orchestrator_current_slot)"
    if test -n "$current_slot" && test "$current_slot" != "$last_side_slot"; then
      orchestrator_trace "10-min boundary: slot=${current_slot} — running buyers"
      last_side_slot="$current_slot"
      if test "$_orch_market_enabled" = "1" || test "$_orch_figurines_enabled" = "1"; then
        buyer_status=0
        orchestrator_run_buyers live || buyer_status=$?
        if test "$buyer_status" -ne 0; then
          orchestrator_trace "buyers exited with status=${buyer_status} — continuing pack loop"
        fi
        # Safe boundary: after buyer sequence
        orchestrator_check_pause
      fi
    fi

    # Recovery check runs AFTER buyers (never interrupts buyers mid-run).
    if test "$_orch_recovery_enabled" = "1"; then
      if recovery_due_now; then
        # Safe boundary: before recovery
        orchestrator_check_pause
        orchestrator_trace "recovery due — running maintenance restart"
        if recovery_run_live; then
          run_metrics_recovery_complete 2>/dev/null || true
        else
          orchestrator_trace "recovery exited non-zero — continuing pack loop"
        fi
        # Safe boundary: after recovery
        orchestrator_check_pause
      fi
    fi
  done
}

orchestrator_usage() {
  printf 'Usage: %s --dry-run [--cycles N]\n' "${BASH_SOURCE[0]}" >&2
  printf '       %s --live\n' "${BASH_SOURCE[0]}" >&2
}

orchestrator_dry_run() {
  local max_cycles="${1:-3}"
  orchestrator_load_config || return 2

  if test "$_orch_pack_enabled" != "1" \
     && test "$_orch_market_enabled" != "1" \
     && test "$_orch_figurines_enabled" != "1"; then
    log_error "orchestrator: all modules disabled — nothing to run"
    return 2
  fi

  printf 'DRY-RUN orchestrator\n'
  printf '  pack_opener:       %s\n' "$(test "$_orch_pack_enabled"      = "1" && printf 'enabled' || printf 'disabled')"
  printf '  market_buyer:      %s\n' "$(test "$_orch_market_enabled"    = "1" && printf 'enabled' || printf 'disabled')"
  printf '  figurines_buyer:   %s\n' "$(test "$_orch_figurines_enabled" = "1" && printf 'enabled' || printf 'disabled')"
  printf '  recovery_restart:  %s\n' "$(test "$_orch_recovery_enabled"  = "1" && printf "enabled (every ${_rec_interval_minutes}min)" || printf 'disabled')"
  printf '  event_voter:       %s\n' "$(test "$_orch_event_voter_enabled" = "1" && printf 'enabled' || printf 'disabled')"
  printf '  buyer_schedule:    every 10 minutes (:00/:10/:20/:30/:40/:50)\n'
  printf '  buyer_order:       Market Buyer → Figurines Buyer\n'
  printf '  recovery_order:    after buyers (never interrupts buyers or pack cycles)\n'
  printf '  cycles_simulated:  %s\n' "$max_cycles"
  printf '\n'

  local i
  for ((i = 1; i <= max_cycles; i++)); do
    printf '%s\n' "--- dry-run cycle $i/$max_cycles ---"

    if test "$_orch_market_enabled" = "1" || test "$_orch_figurines_enabled" = "1"; then
      if test "$i" -eq 1; then
        printf '[simulating buyer run at 10-min boundary]\n'
        orchestrator_run_buyers dry-run || return 2
      fi
    fi

    if test "$_orch_pack_enabled" = "1"; then
      printf '[simulating pack cycle %s]\n' "$i"
      MACRO_INPUT_MODE=dry-run live_cycle_runner_run 1 1 0 0 0 || return 2
    else
      printf '[pack opener disabled — would idle 2s]\n'
    fi

    if test "$_orch_recovery_enabled" = "1"; then
      if test "$i" -eq 1; then
        printf '[simulating recovery restart at interval boundary]\n'
        MACRO_INPUT_MODE=dry-run recovery_run_dry_run || return 2
      fi
    fi
  done

  printf '\nDRY-RUN orchestrator complete (%s cycles simulated)\n' "$max_cycles"
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
      orchestrator_usage
      exit 2
      ;;
  esac

  cycles=3

  while test "$#" -gt 0; do
    case "$1" in
      --cycles)
        shift
        if test "$#" -eq 0; then
          printf 'ERROR: --cycles requires a value\n' >&2
          exit 2
        fi
        if ! [[ "$1" =~ ^[0-9]+$ ]] || test "$1" -lt 1; then
          printf 'ERROR: --cycles must be a positive integer: %s\n' "$1" >&2
          exit 2
        fi
        cycles="$1"
        shift
        ;;
      *)
        orchestrator_usage
        exit 2
        ;;
    esac
  done

  if test "$mode" = "live"; then
    export MACRO_INPUT_MODE=live
    orchestrator_run
  else
    export MACRO_INPUT_MODE=dry-run
    orchestrator_dry_run "$cycles"
  fi
fi
