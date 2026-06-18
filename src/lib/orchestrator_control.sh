#!/usr/bin/env bash
# Orchestrator pause/resume control — file-based state for UI<->orchestrator communication.
# State file: runtime_config/orchestrator/control.state
# Valid states: running  pause_requested  paused  continue_requested

_orch_ctrl_lib_dir="${BASH_SOURCE[0]%/*}"
if test "$_orch_ctrl_lib_dir" = "${BASH_SOURCE[0]}"; then
  _orch_ctrl_lib_dir="."
fi

orchestrator_control_state_file() {
  local root="${MACRO_PROJECT_ROOT:-}"
  if test -z "$root"; then
    root="$(cd "$_orch_ctrl_lib_dir/../.." && pwd -P)"
  fi
  printf '%s/runtime_config/orchestrator/control.state\n' "$root"
}

orchestrator_control_set() {
  local state="$1"
  local file
  file="$(orchestrator_control_state_file)"
  mkdir -p "${file%/*}"
  printf '%s\n' "$state" > "$file"
}

orchestrator_control_get() {
  local file
  file="$(orchestrator_control_state_file)"
  if ! test -f "$file"; then
    printf 'running'
    return 0
  fi
  local state
  state="$(head -n1 "$file" 2>/dev/null || true)"
  printf '%s' "${state:-running}"
}

orchestrator_control_init() {
  orchestrator_control_set "running"
}

orchestrator_control_request_pause() {
  orchestrator_control_set "pause_requested"
}

orchestrator_control_request_continue() {
  orchestrator_control_set "continue_requested"
}

orchestrator_control_clear() {
  local file
  file="$(orchestrator_control_state_file)"
  rm -f "$file"
}
