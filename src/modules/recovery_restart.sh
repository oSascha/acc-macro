#!/usr/bin/env bash
# Recovery Restart — optional Sober/Roblox maintenance restart for long-running lag.
# All live actions are gated behind MACRO_INPUT_MODE=live and MACRO_LIVE_INPUT_ALLOWED=1.
# Direct invocation: ./recovery_restart.sh --dry-run

_recovery_script="${BASH_SOURCE[0]}"
_recovery_dir="${_recovery_script%/*}"
if test "$_recovery_dir" = "$_recovery_script"; then
  _recovery_dir="."
fi

_recovery_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$_recovery_project_root"; then
  _recovery_project_root="$(cd "$_recovery_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$_recovery_project_root/src/lib/config.sh"
# shellcheck source=../lib/input.sh
. "$_recovery_project_root/src/lib/input.sh"

# Overridable file handles for testing
RECOVERY_DEFAULTS_FILE="${RECOVERY_DEFAULTS_FILE:-}"
RECOVERY_POINTS_FILE="${RECOVERY_POINTS_FILE:-}"

# Internal state
_recovery_last_ts=""
_recovery_last_ts_file=""

# Loaded settings
_rec_enabled="0"
_rec_interval_minutes="120"
_rec_url=""
_rec_launch_command="xdg-open"
_rec_kill_before="0"
_rec_post_launch_wait="10m"
_rec_post_popup_wait="500ms"
_rec_select_pack_key="1"
_rec_post_select_wait="500ms"
_rec_open_inventory_wait="500ms"
_rec_post_items_wait="500ms"
_rec_base_spam_count="10"
_rec_base_spam_delay_ms="15"
_rec_post_base_spam_wait="50ms"

# Loaded recovery points
_rec_popup_close_x=""
_rec_popup_close_y=""
_rec_items_tab_x=""
_rec_items_tab_y=""

# Reused from pack opener points.conf (not duplicated in recovery points)
_rec_menu_button_x=""
_rec_menu_button_y=""
_rec_close_button_x=""
_rec_close_button_y=""
_rec_base_teleport_x=""
_rec_base_teleport_y=""

recovery_log() {
  printf 'recovery %s\n' "$*"
}

recovery_trace() {
  if acc_trace_enabled; then
    printf 'TRACE recovery %s\n' "$*"
  fi
}

recovery_load_config() {
  local runtime_dir defaults_file points_file template_dir

  runtime_dir="$(config_recovery_dir)"
  defaults_file="${RECOVERY_DEFAULTS_FILE:-$runtime_dir/defaults.conf}"
  points_file="${RECOVERY_POINTS_FILE:-$runtime_dir/points.conf}"
  _recovery_last_ts_file="$runtime_dir/.last_recovery_ts"

  mkdir -p "$runtime_dir"
  template_dir="$(config_recovery_template_dir)"

  if ! test -f "$defaults_file" && test -f "$template_dir/defaults.conf"; then
    cp "$template_dir/defaults.conf" "$defaults_file"
  fi
  if ! test -f "$points_file" && test -f "$template_dir/points.conf"; then
    cp "$template_dir/points.conf" "$points_file"
  fi

  if test -f "$defaults_file"; then
    # shellcheck source=/dev/null
    . "$defaults_file"
  fi
  if test -f "$points_file"; then
    # shellcheck source=/dev/null
    . "$points_file"
  fi

  _rec_enabled="${RECOVERY_ENABLED:-0}"
  _rec_interval_minutes="${RECOVERY_INTERVAL_MINUTES:-120}"
  _rec_url="${RECOVERY_PRIVATE_SERVER_URL:-}"
  _rec_launch_command="${RECOVERY_LAUNCH_COMMAND:-xdg-open}"
  _rec_kill_before="${RECOVERY_KILL_SOBER_BEFORE_RELAUNCH:-0}"
  _rec_post_launch_wait="${RECOVERY_POST_LAUNCH_WAIT:-10m}"
  _rec_post_popup_wait="${RECOVERY_POST_POPUP_CLOSE_WAIT:-500ms}"
  _rec_select_pack_key="${RECOVERY_SELECT_PACK_KEY:-1}"
  _rec_post_select_wait="${RECOVERY_POST_SELECT_PACK_WAIT:-500ms}"
  _rec_open_inventory_wait="${RECOVERY_OPEN_INVENTORY_WAIT:-500ms}"
  _rec_post_items_wait="${RECOVERY_POST_ITEMS_TAB_WAIT:-500ms}"
  _rec_base_spam_count="${RECOVERY_PRE_RESUME_BASE_SPAM_COUNT:-10}"
  _rec_base_spam_delay_ms="$(parse_duration_ms "${RECOVERY_PRE_RESUME_BASE_SPAM_DELAY:-15ms}")"
  _rec_post_base_spam_wait="${RECOVERY_POST_BASE_SPAM_WAIT:-50ms}"

  _rec_popup_close_x="${RECOVERY_POPUP_CLOSE_BUTTON_X:-}"
  _rec_popup_close_y="${RECOVERY_POPUP_CLOSE_BUTTON_Y:-}"
  _rec_items_tab_x="${RECOVERY_ITEMS_TAB_BUTTON_X:-}"
  _rec_items_tab_y="${RECOVERY_ITEMS_TAB_BUTTON_Y:-}"

  # Reuse MENU_BUTTON and BASE_TELEPORT_BUTTON from pack opener points.
  # These are not duplicated in recovery/points.conf to avoid drift.
  local pack_points_file
  pack_points_file="$(config_pack_opener_dir)/points.conf"
  if test -f "$pack_points_file"; then
    # shellcheck source=/dev/null
    . "$pack_points_file"
    _rec_menu_button_x="${MENU_BUTTON_X:-}"
    _rec_menu_button_y="${MENU_BUTTON_Y:-}"
    _rec_close_button_x="${CLOSE_BUTTON_X:-}"
    _rec_close_button_y="${CLOSE_BUTTON_Y:-}"
    _rec_base_teleport_x="${BASE_TELEPORT_BUTTON_X:-}"
    _rec_base_teleport_y="${BASE_TELEPORT_BUTTON_Y:-}"
  fi

  # Initialize session-start timestamp so recovery is not immediately due.
  if test -z "$_recovery_last_ts"; then
    _recovery_last_ts="$(date +%s)"
  fi
}

# Returns 0 if a recovery restart is currently due, 1 if not.
# Recovery is never due when disabled.
recovery_due_now() {
  if test "$_rec_enabled" != "1"; then
    return 1
  fi

  local now_ts interval_s elapsed_s

  now_ts="$(date +%s)"
  interval_s=$((_rec_interval_minutes * 60))

  if test -z "$_recovery_last_ts"; then
    return 0
  fi

  elapsed_s=$((now_ts - _recovery_last_ts))
  if test "$elapsed_s" -ge "$interval_s"; then
    return 0
  fi
  return 1
}

# Returns 0 if all required recovery config is present.
# If recovery is disabled, only warns about missing config (does not fail).
recovery_preflight() {
  local missing=""

  if test "$_rec_enabled" != "1"; then
    return 0
  fi

  if test -z "$_rec_url"; then
    missing="$missing RECOVERY_PRIVATE_SERVER_URL"
  fi
  if test -z "$_rec_popup_close_x" || test -z "$_rec_popup_close_y"; then
    missing="$missing RECOVERY_POPUP_CLOSE_BUTTON_X/Y"
  fi
  if test -z "$_rec_items_tab_x" || test -z "$_rec_items_tab_y"; then
    missing="$missing RECOVERY_ITEMS_TAB_BUTTON_X/Y"
  fi
  if test -z "$_rec_menu_button_x" || test -z "$_rec_menu_button_y"; then
    missing="$missing MENU_BUTTON_X/Y (from pack opener points.conf)"
  fi
  if test -z "$_rec_close_button_x" || test -z "$_rec_close_button_y"; then
    missing="$missing CLOSE_BUTTON_X/Y (CLOSE_BUTTON is missing from pack opener points config)"
  fi
  if test -z "$_rec_base_teleport_x" || test -z "$_rec_base_teleport_y"; then
    missing="$missing BASE_TELEPORT_BUTTON_X/Y (from pack opener points.conf)"
  fi

  if test -n "$missing"; then
    log_error "recovery preflight failed — missing:$missing"
    return 2
  fi

  return 0
}

# Internal: print the planned recovery sequence without executing any actions.
_recovery_print_sequence() {
  local url_display
  if test -n "$_rec_url"; then
    url_display="[configured]"
  else
    url_display="<not configured>"
  fi

  printf '  recovery_enabled:       %s\n' "$_rec_enabled"
  printf '  recovery_interval:      every %s minutes\n' "$_rec_interval_minutes"
  printf '\n'
  printf '  --- recovery sequence ---\n'
  if test "$_rec_kill_before" = "1"; then
    printf '  step 0: kill Sober: pkill -x sober\n'
  else
    printf '  step 0: kill Sober: skipped (RECOVERY_KILL_SOBER_BEFORE_RELAUNCH=0)\n'
  fi
  printf '  step 1: launch game: %s %s\n' "$_rec_launch_command" "$url_display"
  printf '  step 2: wait for game to load: %s\n' "$_rec_post_launch_wait"
  printf '  step 3: close first-login popup: click (%s, %s)\n' \
    "${_rec_popup_close_x:-<unset>}" "${_rec_popup_close_y:-<unset>}"
  printf '  step 4: wait: %s\n' "$_rec_post_popup_wait"
  printf '  step 5: select pack: tap key "%s"\n' "$_rec_select_pack_key"
  printf '  step 6: wait: %s\n' "$_rec_post_select_wait"
  printf '  step 7: open inventory: click MENU_BUTTON (%s, %s)\n' \
    "${_rec_menu_button_x:-<unset>}" "${_rec_menu_button_y:-<unset>}"
  printf '  step 8: wait: %s\n' "$_rec_open_inventory_wait"
  printf '  step 9: click Items tab: click (%s, %s)\n' \
    "${_rec_items_tab_x:-<unset>}" "${_rec_items_tab_y:-<unset>}"
  printf '  step 10: wait: %s\n' "$_rec_post_items_wait"
  printf '  step 11: close inventory: click CLOSE_BUTTON (%s, %s)\n' \
    "${_rec_close_button_x:-<unset>}" "${_rec_close_button_y:-<unset>}"
  printf '  step 12: base spam: click BASE_TELEPORT_BUTTON (%s, %s) ×%s @ %sms\n' \
    "${_rec_base_teleport_x:-<unset>}" "${_rec_base_teleport_y:-<unset>}" \
    "$_rec_base_spam_count" "$_rec_base_spam_delay_ms"
  printf '  step 13: wait: %s\n' "$_rec_post_base_spam_wait"
  printf '  step 14: resume normal orchestrator loop\n'
  printf '\n'
  printf '  reused from pack opener points.conf:\n'
  printf '    MENU_BUTTON:           (%s, %s)\n' \
    "${_rec_menu_button_x:-<unset>}" "${_rec_menu_button_y:-<unset>}"
  printf '    CLOSE_BUTTON:          (%s, %s)\n' \
    "${_rec_close_button_x:-<unset>}" "${_rec_close_button_y:-<unset>}"
  printf '    BASE_TELEPORT_BUTTON:  (%s, %s)\n' \
    "${_rec_base_teleport_x:-<unset>}" "${_rec_base_teleport_y:-<unset>}"
}

recovery_run_dry_run() {
  recovery_load_config || return 2

  printf 'DRY-RUN recovery\n'
  printf '  mode:                   %s\n' "$(input_mode)"
  _recovery_print_sequence

  if test "$_rec_enabled" = "1"; then
    if ! recovery_preflight; then
      printf '  PREFLIGHT: FAIL — required config is missing (see errors above)\n'
    else
      printf '  PREFLIGHT: OK\n'
    fi
  else
    printf '  PREFLIGHT: skipped (recovery disabled)\n'
  fi
}

# Internal: launch game without using xdotool (xdg-open is a direct shell call).
_recovery_launch_game() {
  local mode
  mode="$(input_mode)" || return 2

  if test "$mode" = "dry-run"; then
    recovery_log "[DRY-RUN] would launch: ${_rec_launch_command} [configured]"
    return 0
  fi

  input_require_live_allowed || return 2

  if test "$_rec_kill_before" = "1"; then
    recovery_log "killing Sober before relaunch: pkill -x sober"
    pkill -x sober || recovery_log "pkill returned non-zero (Sober may not be running)"
    input_sleep 2s || return 2
  fi

  recovery_log "launching game: ${_rec_launch_command} [URL configured]"
  "${_rec_launch_command}" "${_rec_url}"
}

recovery_run_live() {
  recovery_load_config || return 2
  recovery_preflight   || return 2

  local mode
  mode="$(input_mode)" || return 2

  if test "$mode" != "live"; then
    log_error "recovery_run_live called in non-live mode: $mode"
    return 2
  fi
  input_require_live_allowed || return 2

  recovery_log "starting maintenance restart"
  recovery_trace "recovery_run_live begin"

  # Step 0: optionally kill Sober / Step 1: launch
  _recovery_launch_game || return 2
  recovery_trace "game launched — waiting for load: ${_rec_post_launch_wait}"

  # Step 2: long wait for game to load fully
  recovery_log "waiting for game to load: ${_rec_post_launch_wait}"
  input_sleep "$_rec_post_launch_wait" || return 2

  # Step 3: close first-login popup
  recovery_log "closing first-login popup: click (${_rec_popup_close_x}, ${_rec_popup_close_y})"
  recovery_trace "click popup-close at (${_rec_popup_close_x}, ${_rec_popup_close_y})"
  click_point "$_rec_popup_close_x" "$_rec_popup_close_y" || return 2

  # Step 4: post-popup wait
  recovery_trace "wait post-popup ${_rec_post_popup_wait}"
  input_sleep "$_rec_post_popup_wait" || return 2

  # Step 5: press key to select pack
  recovery_log "select pack: tap key '${_rec_select_pack_key}'"
  recovery_trace "tap key ${_rec_select_pack_key}"
  tap_key "$_rec_select_pack_key" || return 2

  # Step 6: post-select wait
  recovery_trace "wait post-select ${_rec_post_select_wait}"
  input_sleep "$_rec_post_select_wait" || return 2

  # Step 7: open inventory via MENU_BUTTON (reused from pack opener points.conf)
  recovery_log "open inventory: click MENU_BUTTON (${_rec_menu_button_x}, ${_rec_menu_button_y})"
  recovery_trace "click MENU_BUTTON at (${_rec_menu_button_x}, ${_rec_menu_button_y})"
  click_point "$_rec_menu_button_x" "$_rec_menu_button_y" || return 2

  # Step 8: wait for inventory to open
  recovery_trace "wait inventory-open ${_rec_open_inventory_wait}"
  input_sleep "$_rec_open_inventory_wait" || return 2

  # Step 9: click Items tab (potions are under Items; inventory opens on Packs by default)
  recovery_log "click Items tab: (${_rec_items_tab_x}, ${_rec_items_tab_y})"
  recovery_trace "click items-tab at (${_rec_items_tab_x}, ${_rec_items_tab_y})"
  click_point "$_rec_items_tab_x" "$_rec_items_tab_y" || return 2

  # Step 10: post-items wait
  recovery_trace "wait post-items ${_rec_post_items_wait}"
  input_sleep "$_rec_post_items_wait" || return 2

  # Step 11: close inventory via CLOSE_BUTTON (red X button; reused from pack opener points.conf)
  recovery_log "close inventory: click CLOSE_BUTTON (${_rec_close_button_x}, ${_rec_close_button_y})"
  recovery_trace "click CLOSE_BUTTON at (${_rec_close_button_x}, ${_rec_close_button_y})"
  click_point "$_rec_close_button_x" "$_rec_close_button_y" || return 2

  # Step 12: base spam on BASE_TELEPORT_BUTTON (reused from pack opener points.conf)
  recovery_log "base spam: BASE_TELEPORT_BUTTON (${_rec_base_teleport_x}, ${_rec_base_teleport_y}) ×${_rec_base_spam_count} @ ${_rec_base_spam_delay_ms}ms"
  recovery_trace "move mouse to base-teleport (${_rec_base_teleport_x}, ${_rec_base_teleport_y})"
  move_mouse "$_rec_base_teleport_x" "$_rec_base_teleport_y" || return 2
  input_click_current_burst "$_rec_base_spam_count" "$_rec_base_spam_delay_ms" || return 2

  # Step 13: post base spam wait
  recovery_trace "wait post-base-spam ${_rec_post_base_spam_wait}"
  input_sleep "$_rec_post_base_spam_wait" || return 2

  # Step 14: record recovery timestamp for interval tracking
  _recovery_last_ts="$(date +%s)"
  recovery_log "maintenance restart complete — resuming orchestrator loop"
  recovery_trace "recovery_run_live complete; next due in ${_rec_interval_minutes} minutes"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:-}" in
    --dry-run)
      export MACRO_INPUT_MODE="${MACRO_INPUT_MODE:-dry-run}"
      recovery_run_dry_run
      ;;
    *)
      printf 'Usage: %s --dry-run\n' "${BASH_SOURCE[0]}" >&2
      exit 2
      ;;
  esac
fi
