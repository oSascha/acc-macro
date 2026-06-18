#!/usr/bin/env bash

macro_input_lib_dir="${BASH_SOURCE[0]%/*}"
if test "$macro_input_lib_dir" = "${BASH_SOURCE[0]}"; then
  macro_input_lib_dir="."
fi

# shellcheck source=env.sh
. "$macro_input_lib_dir/env.sh"
# shellcheck source=logging.sh
. "$macro_input_lib_dir/logging.sh"
# shellcheck source=timing.sh
. "$macro_input_lib_dir/timing.sh"

INPUT_CLICK_BURST_MAX_COUNT="${INPUT_CLICK_BURST_MAX_COUNT:-1500}"
INPUT_CLICK_BURST_MAX_DELAY_MS="${INPUT_CLICK_BURST_MAX_DELAY_MS:-1000}"
INPUT_KEY_TAP_BURST_MAX_COUNT="${INPUT_KEY_TAP_BURST_MAX_COUNT:-1000}"
INPUT_KEY_TAP_BURST_MAX_DELAY_MS="${INPUT_KEY_TAP_BURST_MAX_DELAY_MS:-1000}"

input_mode() {
  local mode="${MACRO_INPUT_MODE:-dry-run}"

  case "$mode" in
    dry-run|live)
      printf '%s\n' "$mode"
      ;;
    *)
      log_error "unsupported MACRO_INPUT_MODE: $mode"
      return 2
      ;;
  esac
}

input_require_live_allowed() {
  local display

  if test "${MACRO_LIVE_INPUT_ALLOWED:-}" != "1"; then
    log_error "live input blocked: set MACRO_LIVE_INPUT_ALLOWED=1 to allow live mode"
    return 2
  fi

  display="$(macro_attached_display)"
  if test -z "$display"; then
    log_error "live input blocked: no DISPLAY found in $(macro_attached_env_file)"
    return 2
  fi

  return 0
}

trace_event() {
  if acc_trace_enabled; then
    printf 'TRACE input %s\n' "$*"
  fi
}

input_validate_integer() {
  local name="$1"
  local value="$2"

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    log_error "$name must be a non-negative integer: $value"
    return 2
  fi
}

input_validate_click_burst() {
  local count="${1:-}"
  local delay_ms="${2:-}"

  if ! [[ "$INPUT_CLICK_BURST_MAX_COUNT" =~ ^[0-9]+$ ]] ||
    test "$INPUT_CLICK_BURST_MAX_COUNT" -lt 1; then
    log_error "INPUT_CLICK_BURST_MAX_COUNT must be a positive integer: $INPUT_CLICK_BURST_MAX_COUNT"
    return 2
  fi

  if ! [[ "$INPUT_CLICK_BURST_MAX_DELAY_MS" =~ ^[0-9]+$ ]]; then
    log_error "INPUT_CLICK_BURST_MAX_DELAY_MS must be a non-negative integer: $INPUT_CLICK_BURST_MAX_DELAY_MS"
    return 2
  fi

  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    log_error "click burst count must be a positive integer: $count"
    return 2
  fi

  if test "$count" -lt 1; then
    log_error "click burst count must be at least 1: $count"
    return 2
  fi

  if test "$count" -gt "$INPUT_CLICK_BURST_MAX_COUNT"; then
    log_error "click burst count exceeds max $INPUT_CLICK_BURST_MAX_COUNT: $count"
    return 2
  fi

  if ! [[ "$delay_ms" =~ ^[0-9]+$ ]]; then
    log_error "click burst delay_ms must be a non-negative integer: $delay_ms"
    return 2
  fi

  if test "$delay_ms" -gt "$INPUT_CLICK_BURST_MAX_DELAY_MS"; then
    log_error "click burst delay_ms exceeds max $INPUT_CLICK_BURST_MAX_DELAY_MS: $delay_ms"
    return 2
  fi
}

input_run_xdotool() {
  local mode
  local display

  mode="$(input_mode)" || return 2

  if test "$mode" = "dry-run"; then
    trace_event "dry-run DISPLAY=$(macro_attached_display) xdotool $*"
    return 0
  fi

  input_require_live_allowed || return 2
  display="$(macro_attached_display)"
  DISPLAY="$display" xdotool "$@"
}

move_mouse() {
  local x="${1:-}"
  local y="${2:-}"

  input_validate_integer "X" "$x" || return 2
  input_validate_integer "Y" "$y" || return 2
  input_run_xdotool mousemove "$x" "$y"
}

click_point() {
  local x="${1:-}"
  local y="${2:-}"

  input_validate_integer "X" "$x" || return 2
  input_validate_integer "Y" "$y" || return 2
  move_mouse "$x" "$y" || return 2
  input_run_xdotool click 1
}

input_click_current() {
  local mode

  mode="$(input_mode)" || return 2
  trace_event "$mode click_current button=1"
  input_run_xdotool click 1
}

input_click_current_burst() {
  local count="${1:-}"
  local delay_ms="${2:-}"
  local mode

  input_validate_click_burst "$count" "$delay_ms" || return 2
  mode="$(input_mode)" || return 2
  trace_event "$mode click_current_burst count=${count} delay_ms=${delay_ms} button=1"
  input_run_xdotool click --repeat "$count" --delay "$delay_ms" 1
}

input_validate_safe_key() {
  local key="${1:-}"

  case "$key" in
    e)
      return 0
      ;;
    *)
      log_error "key tap burst only supports the safe key 'e': $key"
      return 2
      ;;
  esac
}

input_validate_key_tap_burst() {
  local key="${1:-}"
  local count="${2:-}"
  local delay_ms="${3:-}"

  input_validate_safe_key "$key" || return 2

  if ! [[ "$INPUT_KEY_TAP_BURST_MAX_COUNT" =~ ^[0-9]+$ ]] ||
    test "$INPUT_KEY_TAP_BURST_MAX_COUNT" -lt 1; then
    log_error "INPUT_KEY_TAP_BURST_MAX_COUNT must be a positive integer: $INPUT_KEY_TAP_BURST_MAX_COUNT"
    return 2
  fi

  if ! [[ "$INPUT_KEY_TAP_BURST_MAX_DELAY_MS" =~ ^[0-9]+$ ]]; then
    log_error "INPUT_KEY_TAP_BURST_MAX_DELAY_MS must be a non-negative integer: $INPUT_KEY_TAP_BURST_MAX_DELAY_MS"
    return 2
  fi

  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    log_error "key tap burst count must be a positive integer: $count"
    return 2
  fi

  if test "$count" -lt 1; then
    log_error "key tap burst count must be at least 1: $count"
    return 2
  fi

  if test "$count" -gt "$INPUT_KEY_TAP_BURST_MAX_COUNT"; then
    log_error "key tap burst count exceeds max $INPUT_KEY_TAP_BURST_MAX_COUNT: $count"
    return 2
  fi

  if ! [[ "$delay_ms" =~ ^[0-9]+$ ]]; then
    log_error "key tap burst delay_ms must be a non-negative integer: $delay_ms"
    return 2
  fi

  if test "$delay_ms" -gt "$INPUT_KEY_TAP_BURST_MAX_DELAY_MS"; then
    log_error "key tap burst delay_ms exceeds max $INPUT_KEY_TAP_BURST_MAX_DELAY_MS: $delay_ms"
    return 2
  fi
}

input_key_tap_burst() {
  local key="${1:-}"
  local count="${2:-}"
  local delay_ms="${3:-}"
  local mode
  local args
  local i

  input_validate_key_tap_burst "$key" "$count" "$delay_ms" || return 2
  mode="$(input_mode)" || return 2
  trace_event "$mode key_tap_burst key=${key} count=${count} delay_ms=${delay_ms}"

  # Single bounded foreground xdotool invocation with repeated key arguments,
  # no background worker and no unbounded repeat.
  args=(key --delay "$delay_ms")
  for ((i = 1; i <= count; i++)); do
    args+=("$key")
  done
  input_run_xdotool "${args[@]}"
}

keydown() {
  local key="${1:-}"

  if test -z "$key"; then
    log_error "keydown requires a key"
    return 2
  fi

  input_run_xdotool keydown "$key"
}

keyup() {
  local key="${1:-}"

  if test -z "$key"; then
    log_error "keyup requires a key"
    return 2
  fi

  input_run_xdotool keyup "$key"
}

tap_key() {
  local key="${1:-}"

  if test -z "$key"; then
    log_error "tap_key requires a key"
    return 2
  fi

  input_run_xdotool key "$key"
}

release_all_inputs() {
  keyup w || return 2
  keyup a || return 2
  keyup s || return 2
  keyup d || return 2
  keyup e || return 2
  input_run_xdotool mouseup 1
}

input_sleep() {
  local value="${1:-}"
  local mode
  local ms

  mode="$(input_mode)" || return 2
  ms="$(parse_duration_ms "$value")" || return 2
  trace_event "$mode sleep ${ms}ms"

  if test "$mode" = "live"; then
    input_require_live_allowed || return 2
  fi

  sleep_duration "$value"
}
