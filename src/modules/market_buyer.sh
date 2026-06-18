#!/usr/bin/env bash
# Market Buyer module — adapted from background-gamescope-market-buyer-v2

_market_buyer_script="${BASH_SOURCE[0]}"
_market_buyer_dir="${_market_buyer_script%/*}"
if test "$_market_buyer_dir" = "$_market_buyer_script"; then
  _market_buyer_dir="."
fi

_market_buyer_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$_market_buyer_project_root"; then
  _market_buyer_project_root="$(cd "$_market_buyer_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$_market_buyer_project_root/src/lib/config.sh"
# shellcheck source=../lib/input.sh
. "$_market_buyer_project_root/src/lib/input.sh"

# Runtime config handles (overridable for testing)
MARKET_BUYER_DEFAULTS_FILE="${MARKET_BUYER_DEFAULTS_FILE:-}"
MARKET_BUYER_POINTS_FILE="${MARKET_BUYER_POINTS_FILE:-}"

# Settings (populated by market_buyer_load_settings)
_mb_base_reset_count=""
_mb_base_reset_delay_ms=""
_mb_pre_reset_wait=""
_mb_post_base_wait=""
_mb_walk_forward_duration=""
_mb_menu_open_wait=""
_mb_post_buy_wait=""
_mb_walk_back_duration=""

# Points (populated by market_buyer_load_points)
_mb_top_market_x=""
_mb_top_market_y=""
_mb_buy_all_x=""
_mb_buy_all_y=""

market_buyer_trace() {
  if acc_trace_enabled; then
    printf 'TRACE market-buyer %s\n' "$*"
  fi
}

market_buyer_log() {
  printf 'market-buyer %s\n' "$*"
}

market_buyer_load_settings() {
  local runtime_dir defaults_file
  runtime_dir="$(config_market_buyer_dir)"
  defaults_file="${MARKET_BUYER_DEFAULTS_FILE:-$runtime_dir/defaults.conf}"

  config_bootstrap_buyer market_buyer

  if ! test -f "$defaults_file"; then
    log_error "market buyer defaults not found: $defaults_file"
    return 2
  fi

  # shellcheck source=/dev/null
  . "$defaults_file"

  _mb_base_reset_count="${BASE_CAMERA_RESET_COUNT:-10}"
  _mb_base_reset_delay_ms="$(parse_duration_ms "${BASE_CAMERA_RESET_DELAY:-15ms}")"
  _mb_pre_reset_wait="${PRE_RESET_WAIT:-50ms}"
  _mb_post_base_wait="${POST_BASE_WAIT:-300ms}"
  _mb_walk_forward_duration="${WALK_FORWARD_DURATION:-1s200ms}"
  _mb_menu_open_wait="${MENU_OPEN_WAIT:-500ms}"
  _mb_post_buy_wait="${POST_BUY_WAIT:-500ms}"
  _mb_walk_back_duration="${WALK_BACK_DURATION:-800ms}"
}

market_buyer_load_points() {
  local runtime_dir points_file
  runtime_dir="$(config_market_buyer_dir)"
  points_file="${MARKET_BUYER_POINTS_FILE:-$runtime_dir/points.conf}"

  config_bootstrap_buyer market_buyer

  if ! test -f "$points_file"; then
    log_error "market buyer points not found: $points_file"
    return 2
  fi

  # shellcheck source=/dev/null
  . "$points_file"

  _mb_top_market_x="${TOP_MARKET_BUTTON_X:-}"
  _mb_top_market_y="${TOP_MARKET_BUTTON_Y:-}"
  _mb_buy_all_x="${MARKET_BUY_ALL_X:-}"
  _mb_buy_all_y="${MARKET_BUY_ALL_Y:-}"
}

market_buyer_get_point() {
  local name="$1"
  local x y
  case "$name" in
    top_market)   x="$_mb_top_market_x"; y="$_mb_top_market_y" ;;
    buy_all)      x="$_mb_buy_all_x";    y="$_mb_buy_all_y"    ;;
    *) log_error "market_buyer_get_point: unknown point: $name"; return 2 ;;
  esac
  if test -z "$x" || test -z "$y"; then
    case "$name" in
      top_market) log_error "market buyer point 'top_market' not configured — set TOP_MARKET_BUTTON_X / TOP_MARKET_BUTTON_Y in $(config_market_buyer_dir)/points.conf" ;;
      buy_all)    log_error "market buyer point 'buy_all' not configured — set MARKET_BUY_ALL_X / MARKET_BUY_ALL_Y in $(config_market_buyer_dir)/points.conf" ;;
      *)          log_error "market buyer point '$name' has empty coordinates" ;;
    esac
    return 2
  fi
  printf '%s %s\n' "$x" "$y"
}

market_buyer_preflight() {
  market_buyer_load_settings || return 2
  market_buyer_load_points   || return 2
  market_buyer_get_point top_market > /dev/null || return 2
  market_buyer_get_point buy_all    > /dev/null || return 2
}

market_buyer_run() {
  market_buyer_preflight || return 2

  local top_x top_y buy_x buy_y coords

  coords="$(market_buyer_get_point top_market)" || return 2
  top_x="${coords%% *}"; top_y="${coords##* }"

  coords="$(market_buyer_get_point buy_all)" || return 2
  buy_x="${coords%% *}"; buy_y="${coords##* }"

  market_buyer_trace "run start"

  # Transition wait before reset spam (gives the game state time to settle)
  market_buyer_log "pre-reset wait ${_mb_pre_reset_wait}"
  market_buyer_trace "pre-reset transition wait ${_mb_pre_reset_wait}"
  input_sleep "$_mb_pre_reset_wait" || return 2

  # Base camera reset: fast burst on TOP_MARKET_BUTTON (no wiggle)
  market_buyer_log "reset spam: point=TOP_MARKET_BUTTON (${top_x},${top_y}) count=${_mb_base_reset_count} delay=${_mb_base_reset_delay_ms}ms"
  move_mouse "$top_x" "$top_y" || return 2
  input_click_current_burst "$_mb_base_reset_count" "$_mb_base_reset_delay_ms" || return 2
  market_buyer_trace "wait post-base ${_mb_post_base_wait}"
  market_buyer_log "reset spam complete"
  input_sleep "$_mb_post_base_wait" || return 2

  # Walk forward to market stall
  market_buyer_log "walk W ${_mb_walk_forward_duration}"
  market_buyer_trace "walk W for ${_mb_walk_forward_duration}"
  keydown w || return 2
  input_sleep "$_mb_walk_forward_duration" || return 2
  keyup w || return 2

  market_buyer_trace "wait menu-open ${_mb_menu_open_wait}"
  input_sleep "$_mb_menu_open_wait" || return 2

  # Buy all
  market_buyer_log "buy MARKET_BUY_ALL (${buy_x},${buy_y})"
  market_buyer_trace "click buy-all at (${buy_x},${buy_y})"
  click_point "$buy_x" "$buy_y" || return 2
  market_buyer_trace "wait post-buy ${_mb_post_buy_wait}"
  input_sleep "$_mb_post_buy_wait" || return 2

  # Walk back
  market_buyer_log "walk S ${_mb_walk_back_duration}"
  market_buyer_trace "walk S back for ${_mb_walk_back_duration}"
  keydown s || return 2
  input_sleep "$_mb_walk_back_duration" || return 2
  keyup s || return 2

  market_buyer_log "complete"
  market_buyer_trace "run complete"
}

market_buyer_dry_run() {
  market_buyer_preflight || return 2

  local top_x top_y buy_x buy_y coords

  coords="$(market_buyer_get_point top_market)" || return 2
  top_x="${coords%% *}"; top_y="${coords##* }"

  coords="$(market_buyer_get_point buy_all)" || return 2
  buy_x="${coords%% *}"; buy_y="${coords##* }"

  printf 'DRY-RUN market-buyer\n'
  printf '  mode:               %s\n' "$(input_mode)"
  printf '  top_market_button:  (%s, %s)\n' "$top_x" "$top_y"
  printf '  buy_all:            (%s, %s)\n' "$buy_x" "$buy_y"
  printf '  base_reset:         ×%s @ %sms (fast burst, no wiggle)\n' "$_mb_base_reset_count" "$_mb_base_reset_delay_ms"
  printf '  pre_reset_wait:     %s\n' "$_mb_pre_reset_wait"
  printf '  post_base_wait:     %s\n' "$_mb_post_base_wait"
  printf '  walk_forward:       W for %s\n' "$_mb_walk_forward_duration"
  printf '  menu_open_wait:     %s\n' "$_mb_menu_open_wait"
  printf '  post_buy_wait:      %s\n' "$_mb_post_buy_wait"
  printf '  walk_back:          S for %s\n' "$_mb_walk_back_duration"

  MACRO_INPUT_MODE=dry-run market_buyer_run || return 2
}
