#!/usr/bin/env bash

log_info() {
  printf 'INFO: %s\n' "$*" >&2
}

log_warn() {
  printf 'WARN: %s\n' "$*" >&2
}

log_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# Trace is on in dry-run (always) or live when ACC_DEBUG_TRACE=1.
acc_trace_enabled() {
  test "${MACRO_INPUT_MODE:-dry-run}" = "dry-run" || test "${ACC_DEBUG_TRACE:-0}" = "1"
}
