#!/usr/bin/env bash

potion_runner_script="${BASH_SOURCE[0]}"
potion_runner_dir="${potion_runner_script%/*}"
if test "$potion_runner_dir" = "$potion_runner_script"; then
  potion_runner_dir="."
fi

potion_runner_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$potion_runner_project_root"; then
  potion_runner_project_root="$(cd "$potion_runner_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$potion_runner_project_root/src/lib/config.sh"
# shellcheck source=../lib/points.sh
. "$potion_runner_project_root/src/lib/points.sh"
# shellcheck source=../lib/potion_plan.sh
. "$potion_runner_project_root/src/lib/potion_plan.sh"
# shellcheck source=../lib/input.sh
. "$potion_runner_project_root/src/lib/input.sh"

__potion_runner_prepared=0
__potion_runner_pre_menu_wait=""
__potion_runner_post_inventory_open_wait=""
__potion_runner_click_interval=""
__potion_runner_close_inventory=""
__potion_runner_plan_has_work=0
__potion_runner_final_active_tier=""

potion_runner_trace() {
  printf 'TRACE potion-runner %s\n' "$*"
}

potion_runner_now_ms() {
  date +%s%3N
}

potion_runner_validate_timing_key() {
  local key="$1"
  local value
  local ms

  value="$(timing_get "$key")" || return 2
  ms="$(parse_duration_ms "$value")" || return 2
  printf 'OK: runner timing %s = %s (%sms)\n' "$key" "$value" "$ms"
}

potion_runner_load_context() {
  local runtime_dir
  local points_file="${POTION_RUNNER_POINTS_FILE:-}"
  local timing_file="${POTION_RUNNER_TIMING_FILE:-}"
  local potion_plan_file="${POTION_RUNNER_POTION_PLAN_FILE:-}"

  if test -z "$points_file" || test -z "$timing_file" || test -z "$potion_plan_file"; then
    runtime_dir="$(config_pack_opener_dir)"
    config_bootstrap_pack_opener_from_templates
    points_file="${points_file:-$runtime_dir/points.conf}"
    timing_file="${timing_file:-$runtime_dir/timing.conf}"
    potion_plan_file="${potion_plan_file:-$(config_pack_opener_potion_plan_file)}"
  fi

  points_load "$points_file"
  timing_load "$timing_file"
  potion_plan_load "$potion_plan_file"
}

potion_runner_resolve_point() {
  local name="${1:-}"

  if test -z "$name"; then
    printf 'ERROR: potion_runner_resolve_point requires a point name\n' >&2
    return 2
  fi

  points_get "$name"
}

potion_runner_resolve_10x_button() {
  local tier="${1:-}"
  local canonical="POTION_${tier}_USE_10X_BUTTON"

  case "$tier" in
    2_MIN|6_MIN|15_MIN)
      ;;
    *)
      printf 'ERROR: unsupported potion tier for 10x button: %s\n' "$tier" >&2
      return 2
      ;;
  esac

  if points_is_set "$canonical"; then
    printf '%s\n' "$canonical"
    return 0
  fi

  if test "$tier" = "2_MIN" && points_is_set USE_10X_BUTTON; then
    printf '%s\n' "USE_10X_BUTTON"
    return 0
  fi

  printf 'ERROR: required 10x point unavailable: %s\n' "$canonical" >&2
  return 1
}

potion_runner_resolve_single_button() {
  local tier="${1:-}"
  local name="POTION_${tier}_USE_SINGLE_BUTTON"

  case "$tier" in
    2_MIN|6_MIN|15_MIN)
      ;;
    *)
      printf 'ERROR: unsupported potion tier for single button: %s\n' "$tier" >&2
      return 2
      ;;
  esac

  if points_is_set "$name"; then
    printf '%s\n' "$name"
    return 0
  fi

  printf 'ERROR: required single-use point unavailable: %s\n' "$name" >&2
  return 1
}

potion_runner_preflight() {
  local failures=0
  local tier
  local enabled
  local amount
  local decomposed
  local ten_x_clicks
  local single_clicks
  local resolved
  local required_timing
  local plan_has_work=0

  potion_plan_validate || failures=$((failures + 1))
  potion_plan_preflight_inventory || failures=$((failures + 1))

  for required_timing in POTION_PRE_MENU_CLICK_WAIT POST_INVENTORY_OPEN_WAIT POST_POTION_SELECT_WAIT POST_POTION_TIER_WAIT POST_POTION_SEQUENCE_WAIT; do
    potion_runner_validate_timing_key "$required_timing" || failures=$((failures + 1))
  done

  potion_plan_get_duration POTION_NAV_CLICK_INTERVAL >/dev/null || failures=$((failures + 1))
  potion_plan_get_duration POTION_CLICK_INTERVAL >/dev/null || failures=$((failures + 1))

  if test "$(potion_plan_get_bool POTION_PLAN_ENABLED 2>/dev/null || printf 0)" != "1"; then
    test "$failures" -eq 0
    return
  fi

  for tier in 2_MIN 6_MIN 15_MIN; do
    enabled="$(potion_plan_tier_enabled "$tier")" || return 2
    amount="$(potion_plan_tier_use_amount "$tier")" || return 2

    if test "$enabled" != "1" || test "$amount" -eq 0; then
      continue
    fi

    plan_has_work=1
    potion_runner_resolve_point "POTION_${tier}" >/dev/null || failures=$((failures + 1))

    decomposed="$(potion_plan_decompose_amount "$amount")" || return 2
    ten_x_clicks="${decomposed%% *}"
    single_clicks="${decomposed#* }"

    if test "$ten_x_clicks" -gt 0; then
      if resolved="$(potion_runner_resolve_10x_button "$tier")"; then
        potion_runner_resolve_point "$resolved" >/dev/null || failures=$((failures + 1))
      else
        failures=$((failures + 1))
      fi
    fi

    if test "$single_clicks" -gt 0; then
      if resolved="$(potion_runner_resolve_single_button "$tier")"; then
        potion_runner_resolve_point "$resolved" >/dev/null || failures=$((failures + 1))
      else
        failures=$((failures + 1))
      fi
    fi
  done

  if test "$plan_has_work" = "1"; then
    potion_runner_resolve_point MENU_BUTTON >/dev/null || failures=$((failures + 1))
  fi

  if test "$plan_has_work" = "1" && test "$(potion_plan_get_bool CLOSE_INVENTORY)" = "1"; then
    potion_runner_resolve_point CLOSE_BUTTON >/dev/null || failures=$((failures + 1))
  fi

  test "$failures" -eq 0
}

potion_runner_plan_has_work() {
  local tier
  local enabled
  local amount

  if test "$(potion_plan_get_bool POTION_PLAN_ENABLED)" != "1"; then
    return 1
  fi

  for tier in 2_MIN 6_MIN 15_MIN; do
    enabled="$(potion_plan_tier_enabled "$tier")" || return 2
    amount="$(potion_plan_tier_use_amount "$tier")" || return 2

    if test "$enabled" = "1" && test "$amount" -gt 0; then
      return 0
    fi
  done

  return 1
}

potion_runner_prepare_for_cycle_loop() {
  potion_runner_load_context || return $?
  potion_runner_preflight || return $?

  __potion_runner_pre_menu_wait="$(timing_get POTION_PRE_MENU_CLICK_WAIT)" || return 2
  __potion_runner_post_inventory_open_wait="$(timing_get POST_INVENTORY_OPEN_WAIT)" || return 2
  __potion_runner_click_interval="$(potion_plan_get_duration POTION_CLICK_INTERVAL)" || return 2
  __potion_runner_close_inventory="$(potion_plan_get_bool CLOSE_INVENTORY)" || return 2

  if potion_runner_plan_has_work; then
    __potion_runner_plan_has_work=1
  else
    __potion_runner_plan_has_work=0
  fi

  __potion_runner_final_active_tier=""
  if test "$__potion_runner_plan_has_work" = "1"; then
    local _prep_t _prep_te _prep_ta
    for _prep_t in 2_MIN 6_MIN 15_MIN; do
      _prep_te="$(potion_plan_tier_enabled "$_prep_t")" || true
      _prep_ta="$(potion_plan_tier_use_amount "$_prep_t")" || true
      if test "${_prep_te:-0}" = "1" && test "${_prep_ta:-0}" -gt 0 2>/dev/null; then
        __potion_runner_final_active_tier="$_prep_t"
      fi
    done
  fi

  __potion_runner_prepared=1
  potion_runner_trace "prepared pre_menu_wait=${__potion_runner_pre_menu_wait} post_inventory_open_wait=${__potion_runner_post_inventory_open_wait} click_interval=${__potion_runner_click_interval} close_inventory=${__potion_runner_close_inventory} plan_has_work=${__potion_runner_plan_has_work} final_active_tier=${__potion_runner_final_active_tier}"
}

potion_runner_click_named_point() {
  local name="$1"
  local point
  local x
  local y

  point="$(potion_runner_resolve_point "$name")" || return $?
  x="${point%,*}"
  y="${point#*,}"
  potion_runner_trace "click point=${name} x=${x} y=${y}"
  click_point "$x" "$y"
}

potion_runner_print_projected_inventory() {
  local tier
  local enabled
  local amount
  local inventory
  local projected

  for tier in 2_MIN 6_MIN 15_MIN; do
    enabled="$(potion_plan_tier_enabled "$tier")" || return 2
    amount="$(potion_plan_tier_use_amount "$tier")" || return 2
    inventory="$(potion_plan_tier_inventory "$tier")" || return 2

    if test "$enabled" != "1" || test "$amount" -eq 0; then
      continue
    fi

    projected=$((inventory - amount))
    potion_runner_trace "projected_inventory tier=${tier} before=${inventory} used=${amount} after=${projected}"
  done
}

potion_runner_run() {
  local tier
  local enabled
  local amount
  local decomposed
  local ten_x_clicks
  local single_clicks
  local tier_button
  local ten_x_button
  local single_button
  local i
  local pre_menu_wait
  local post_inventory_open_wait
  local click_interval
  local close_inventory

  if test "${__potion_runner_prepared:-0}" = "1"; then
    pre_menu_wait="$__potion_runner_pre_menu_wait"
    post_inventory_open_wait="$__potion_runner_post_inventory_open_wait"
    click_interval="$__potion_runner_click_interval"
    close_inventory="$__potion_runner_close_inventory"
  else
    potion_runner_load_context || return $?
    potion_runner_preflight || return $?
    pre_menu_wait="$(timing_get POTION_PRE_MENU_CLICK_WAIT)" || return 2
    post_inventory_open_wait="$(timing_get POST_INVENTORY_OPEN_WAIT)" || return 2
    click_interval="$(potion_plan_get_duration POTION_CLICK_INTERVAL)" || return 2
    close_inventory="$(potion_plan_get_bool CLOSE_INVENTORY)" || return 2
  fi

  potion_runner_trace "start"
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    potion_runner_trace "transition base_to_menu potion_runner_enter_ms=$(potion_runner_now_ms)"
    potion_runner_trace "transition base_to_menu release_all_inputs_start_ms=$(potion_runner_now_ms)"
  fi
  release_all_inputs || return 2
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    potion_runner_trace "transition base_to_menu release_all_inputs_done_ms=$(potion_runner_now_ms)"
  fi
  potion_runner_trace "pre_menu_wait key=POTION_PRE_MENU_CLICK_WAIT duration=${pre_menu_wait}"
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    potion_runner_trace "transition base_to_menu pre_menu_wait_start key=POTION_PRE_MENU_CLICK_WAIT duration=${pre_menu_wait}"
  fi
  input_sleep "$pre_menu_wait" || return 2
  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    potion_runner_trace "transition base_to_menu pre_menu_wait_done_ms=$(potion_runner_now_ms)"
  fi

  if test "${__potion_runner_prepared:-0}" = "1"; then
    if test "$__potion_runner_plan_has_work" != "1"; then
      potion_runner_trace "skipped no_active_tiers=1"
      potion_runner_print_projected_inventory
      input_sleep "$(timing_get POST_POTION_SEQUENCE_WAIT)" || return 2
      release_all_inputs || return 2
      potion_runner_trace "complete"
      return 0
    fi
  else
    if test "$(potion_plan_get_bool POTION_PLAN_ENABLED)" != "1"; then
      potion_runner_trace "skipped enabled=0"
      potion_runner_print_projected_inventory
      input_sleep "$(timing_get POST_POTION_SEQUENCE_WAIT)" || return 2
      release_all_inputs || return 2
      potion_runner_trace "complete"
      return 0
    fi

    if ! potion_runner_plan_has_work; then
      potion_runner_trace "skipped no_active_tiers=1"
      potion_runner_print_projected_inventory
      input_sleep "$(timing_get POST_POTION_SEQUENCE_WAIT)" || return 2
      release_all_inputs || return 2
      potion_runner_trace "complete"
      return 0
    fi
  fi

  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    local _menu_click_ms
    _menu_click_ms="$(potion_runner_now_ms)"
    local _transition_total=""
    if test -n "${__lcr_transition_start_ms:-}"; then
      _transition_total="$((_menu_click_ms - __lcr_transition_start_ms))"
    fi
    potion_runner_trace "transition base_to_menu menu_click_start point=MENU_BUTTON ms=${_menu_click_ms}"
    if test -n "$_transition_total"; then
      potion_runner_trace "transition base_to_menu total_ms=${_transition_total}"
    fi
  fi
  potion_runner_click_named_point MENU_BUTTON || return 2
  potion_runner_trace "post_inventory_open_wait key=POST_INVENTORY_OPEN_WAIT duration=${post_inventory_open_wait}"
  input_sleep "$post_inventory_open_wait" || return 2

  if test "${MACRO_TRACE_TIMING:-}" = "1"; then
    local _luc_final_tier="" _luc_t _luc_te _luc_ta
    local _luc_final_use_done_ms="" _luc_click_interval_val="" _luc_after_interval_done_ms=""
    local _luc_close_start_ms="" _luc_total_ms=""
    if test "${__potion_runner_prepared:-0}" = "1"; then
      _luc_final_tier="${__potion_runner_final_active_tier:-}"
    else
      for _luc_t in 2_MIN 6_MIN 15_MIN; do
        _luc_te="$(potion_plan_tier_enabled "$_luc_t")" || true
        _luc_ta="$(potion_plan_tier_use_amount "$_luc_t")" || true
        if test "${_luc_te:-0}" = "1" && test "${_luc_ta:-0}" -gt 0 2>/dev/null; then
          _luc_final_tier="$_luc_t"
        fi
      done
    fi
  fi

  for tier in 2_MIN 6_MIN 15_MIN; do
    enabled="$(potion_plan_tier_enabled "$tier")" || return 2
    amount="$(potion_plan_tier_use_amount "$tier")" || return 2

    if test "$enabled" != "1" || test "$amount" -eq 0; then
      potion_runner_trace "tier=${tier} skipped enabled=${enabled} amount=${amount}"
      continue
    fi

    decomposed="$(potion_plan_decompose_amount "$amount")" || return 2
    ten_x_clicks="${decomposed%% *}"
    single_clicks="${decomposed#* }"
    tier_button="POTION_${tier}"

    potion_runner_trace "tier=${tier} amount=${amount} ten_x_clicks=${ten_x_clicks} single_clicks=${single_clicks}"
    potion_runner_click_named_point "$tier_button" || return 2
    input_sleep "$(timing_get POST_POTION_SELECT_WAIT)" || return 2
    input_sleep "$(timing_get POST_POTION_TIER_WAIT)" || return 2

    if test "$ten_x_clicks" -gt 0; then
      ten_x_button="$(potion_runner_resolve_10x_button "$tier")" || return 2
      if test "$tier" = "2_MIN" && test "$ten_x_button" = "USE_10X_BUTTON"; then
        potion_runner_trace "tier=${tier} ten_x_button=POTION_2_MIN_USE_10X_BUTTON ten_x_button_fallback=USE_10X_BUTTON"
      else
        potion_runner_trace "tier=${tier} ten_x_button=${ten_x_button}"
      fi

      for ((i = 1; i <= ten_x_clicks; i++)); do
        potion_runner_trace "tier=${tier} click_type=10x click_index=${i}/${ten_x_clicks} point=${ten_x_button}"
        potion_runner_click_named_point "$ten_x_button" || return 2
        if test "${MACRO_TRACE_TIMING:-}" = "1" && test "$tier" = "${_luc_final_tier:-}" && test "$i" -eq "$ten_x_clicks" && test "$single_clicks" -eq 0; then
          _luc_final_use_done_ms="$(potion_runner_now_ms)"
          _luc_click_interval_val="$click_interval"
          potion_runner_trace "transition last_use_to_close final_use_click_done_ms=${_luc_final_use_done_ms}"
          potion_runner_trace "transition last_use_to_close after_click_interval_start key=POTION_CLICK_INTERVAL duration=${_luc_click_interval_val}"
        fi
        input_sleep "$click_interval" || return 2
        if test "${MACRO_TRACE_TIMING:-}" = "1" && test "$tier" = "${_luc_final_tier:-}" && test "$i" -eq "$ten_x_clicks" && test "$single_clicks" -eq 0; then
          _luc_after_interval_done_ms="$(potion_runner_now_ms)"
          potion_runner_trace "transition last_use_to_close after_click_interval_done_ms=${_luc_after_interval_done_ms}"
          potion_runner_trace "transition last_use_to_close disabled_tier_checks_start_ms=${_luc_after_interval_done_ms}"
        fi
      done
    fi

    if test "$single_clicks" -gt 0; then
      single_button="$(potion_runner_resolve_single_button "$tier")" || return 2
      potion_runner_trace "tier=${tier} single_button=${single_button}"
      for ((i = 1; i <= single_clicks; i++)); do
        potion_runner_trace "tier=${tier} click_type=single click_index=${i}/${single_clicks} point=${single_button}"
        potion_runner_click_named_point "$single_button" || return 2
        if test "${MACRO_TRACE_TIMING:-}" = "1" && test "$tier" = "${_luc_final_tier:-}" && test "$i" -eq "$single_clicks"; then
          _luc_final_use_done_ms="$(potion_runner_now_ms)"
          _luc_click_interval_val="$click_interval"
          potion_runner_trace "transition last_use_to_close final_use_click_done_ms=${_luc_final_use_done_ms}"
          potion_runner_trace "transition last_use_to_close after_click_interval_start key=POTION_CLICK_INTERVAL duration=${_luc_click_interval_val}"
        fi
        input_sleep "$click_interval" || return 2
        if test "${MACRO_TRACE_TIMING:-}" = "1" && test "$tier" = "${_luc_final_tier:-}" && test "$i" -eq "$single_clicks"; then
          _luc_after_interval_done_ms="$(potion_runner_now_ms)"
          potion_runner_trace "transition last_use_to_close after_click_interval_done_ms=${_luc_after_interval_done_ms}"
          potion_runner_trace "transition last_use_to_close disabled_tier_checks_start_ms=${_luc_after_interval_done_ms}"
        fi
      done
    fi

    if test "${__potion_runner_prepared:-0}" = "1" && test -n "${__potion_runner_final_active_tier:-}" && test "$tier" = "$__potion_runner_final_active_tier"; then
      break
    fi
  done

  if test "$close_inventory" = "1"; then
    if test "${MACRO_TRACE_TIMING:-}" = "1" && test -n "${_luc_final_use_done_ms:-}"; then
      _luc_close_start_ms="$(potion_runner_now_ms)"
      _luc_total_ms=$((_luc_close_start_ms - _luc_final_use_done_ms))
      potion_runner_trace "transition last_use_to_close disabled_tier_checks_done_ms=${_luc_close_start_ms}"
      potion_runner_trace "transition last_use_to_close close_click_start point=CLOSE_BUTTON ms=${_luc_close_start_ms}"
      potion_runner_trace "transition last_use_to_close total_ms=${_luc_total_ms}"
    fi
    potion_runner_click_named_point CLOSE_BUTTON || return 2
  fi

  input_sleep "$(timing_get POST_POTION_SEQUENCE_WAIT)" || return 2
  potion_runner_print_projected_inventory
  release_all_inputs || return 2
  potion_runner_trace "complete"
}

potion_runner_usage() {
  printf 'Usage: %s --dry-run\n' "$0" >&2
  printf '       %s --live\n' "$0" >&2
}

potion_runner_require_live_gate() {
  if test "${MACRO_INPUT_MODE:-}" != "live" ||
    test "${MACRO_LIVE_INPUT_ALLOWED:-}" != "1" ||
    test "${MACRO_POTION_RUNNER_LIVE_CONFIRM:-}" != "YES"; then
    printf 'ERROR: live potion runner blocked: set MACRO_INPUT_MODE=live MACRO_LIVE_INPUT_ALLOWED=1 MACRO_POTION_RUNNER_LIVE_CONFIRM=YES\n' >&2
    return 2
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:---dry-run}" in
    --dry-run)
      shift || true
      if test "$#" -ne 0; then
        potion_runner_usage
        exit 2
      fi
      export MACRO_INPUT_MODE=dry-run
      potion_runner_run
      ;;
    --live)
      shift || true
      if test "$#" -ne 0; then
        potion_runner_usage
        exit 2
      fi
      potion_runner_require_live_gate
      potion_runner_run
      ;;
    *)
      potion_runner_usage
      exit 2
      ;;
  esac
fi
