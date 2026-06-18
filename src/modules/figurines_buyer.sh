#!/usr/bin/env bash
# Figurines Buyer module — adapted from background-gamescope-shop-buyer-v2
# "Shop buyer" renamed to "Figurines Buyer" in all new code.

_figurines_buyer_script="${BASH_SOURCE[0]}"
_figurines_buyer_dir="${_figurines_buyer_script%/*}"
if test "$_figurines_buyer_dir" = "$_figurines_buyer_script"; then
  _figurines_buyer_dir="."
fi

_figurines_buyer_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$_figurines_buyer_project_root"; then
  _figurines_buyer_project_root="$(cd "$_figurines_buyer_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$_figurines_buyer_project_root/src/lib/config.sh"
# shellcheck source=../lib/input.sh
. "$_figurines_buyer_project_root/src/lib/input.sh"

# Runtime config handles (overridable for testing)
FIGURINES_BUYER_DEFAULTS_FILE="${FIGURINES_BUYER_DEFAULTS_FILE:-}"
FIGURINES_BUYER_POINTS_FILE="${FIGURINES_BUYER_POINTS_FILE:-}"

# Settings (populated by figurines_buyer_load_settings)
_fb_base_reset_count=""
_fb_base_reset_delay_ms=""
_fb_pre_reset_wait=""
_fb_post_base_wait=""
_fb_walk_forward_duration=""
_fb_first_diagonal_duration=""
_fb_teleport_wait=""
_fb_second_diagonal_duration=""
_fb_menu_open_wait=""
_fb_post_buy_wait=""
_fb_walk_away_duration=""

# Points (populated by figurines_buyer_load_points)
_fb_base_teleport_x=""
_fb_base_teleport_y=""
_fb_buy_all_x=""
_fb_buy_all_y=""

figurines_buyer_trace() {
  if acc_trace_enabled; then
    printf 'TRACE figurines-buyer %s\n' "$*"
  fi
}

figurines_buyer_log() {
  printf 'figurines-buyer %s\n' "$*"
}

figurines_buyer_load_settings() {
  local runtime_dir defaults_file
  runtime_dir="$(config_figurines_buyer_dir)"
  defaults_file="${FIGURINES_BUYER_DEFAULTS_FILE:-$runtime_dir/defaults.conf}"

  config_bootstrap_buyer figurines_buyer

  if ! test -f "$defaults_file"; then
    log_error "figurines buyer defaults not found: $defaults_file"
    return 2
  fi

  # shellcheck source=/dev/null
  . "$defaults_file"

  _fb_base_reset_count="${BASE_CAMERA_RESET_COUNT:-10}"
  _fb_base_reset_delay_ms="$(parse_duration_ms "${BASE_CAMERA_RESET_DELAY:-15ms}")"
  _fb_pre_reset_wait="${PRE_RESET_WAIT:-50ms}"
  _fb_post_base_wait="${POST_BASE_WAIT:-250ms}"
  _fb_walk_forward_duration="${WALK_FORWARD_DURATION:-1s300ms}"
  _fb_first_diagonal_duration="${FIRST_DIAGONAL_DURATION:-1s500ms}"
  _fb_teleport_wait="${TELEPORT_WAIT:-1s}"
  _fb_second_diagonal_duration="${SECOND_DIAGONAL_DURATION:-1s500ms}"
  _fb_menu_open_wait="${MENU_OPEN_WAIT:-200ms}"
  _fb_post_buy_wait="${POST_BUY_WAIT:-700ms}"
  _fb_walk_away_duration="${WALK_AWAY_LEFT_DURATION:-600ms}"
}

figurines_buyer_load_points() {
  local runtime_dir points_file
  runtime_dir="$(config_figurines_buyer_dir)"
  points_file="${FIGURINES_BUYER_POINTS_FILE:-$runtime_dir/points.conf}"

  config_bootstrap_buyer figurines_buyer

  if ! test -f "$points_file"; then
    log_error "figurines buyer points not found: $points_file"
    return 2
  fi

  # shellcheck source=/dev/null
  . "$points_file"

  _fb_base_teleport_x="${BASE_TELEPORT_BUTTON_X:-}"
  _fb_base_teleport_y="${BASE_TELEPORT_BUTTON_Y:-}"
  _fb_buy_all_x="${FIGURINES_BUY_ALL_X:-}"
  _fb_buy_all_y="${FIGURINES_BUY_ALL_Y:-}"
}

figurines_buyer_get_point() {
  local name="$1"
  local x y
  case "$name" in
    base_teleport) x="$_fb_base_teleport_x"; y="$_fb_base_teleport_y" ;;
    buy_all)       x="$_fb_buy_all_x";       y="$_fb_buy_all_y"       ;;
    *) log_error "figurines_buyer_get_point: unknown point: $name"; return 2 ;;
  esac
  if test -z "$x" || test -z "$y"; then
    case "$name" in
      base_teleport) log_error "figurines buyer point 'base_teleport' not configured — set BASE_TELEPORT_BUTTON_X / BASE_TELEPORT_BUTTON_Y in $(config_figurines_buyer_dir)/points.conf" ;;
      buy_all)       log_error "figurines buyer point 'buy_all' not configured — set FIGURINES_BUY_ALL_X / FIGURINES_BUY_ALL_Y in $(config_figurines_buyer_dir)/points.conf" ;;
      *)             log_error "figurines buyer point '$name' has empty coordinates" ;;
    esac
    return 2
  fi
  printf '%s %s\n' "$x" "$y"
}

figurines_buyer_preflight() {
  figurines_buyer_load_settings || return 2
  figurines_buyer_load_points   || return 2
  figurines_buyer_get_point base_teleport > /dev/null || return 2
  figurines_buyer_get_point buy_all       > /dev/null || return 2
}

figurines_buyer_run() {
  figurines_buyer_preflight || return 2

  local base_x base_y buy_x buy_y coords

  coords="$(figurines_buyer_get_point base_teleport)" || return 2
  base_x="${coords%% *}"; base_y="${coords##* }"

  coords="$(figurines_buyer_get_point buy_all)" || return 2
  buy_x="${coords%% *}"; buy_y="${coords##* }"

  figurines_buyer_trace "run start"

  # Transition wait before reset spam (gives the game state time to settle)
  figurines_buyer_log "pre-reset wait ${_fb_pre_reset_wait}"
  figurines_buyer_trace "pre-reset transition wait ${_fb_pre_reset_wait}"
  input_sleep "$_fb_pre_reset_wait" || return 2

  # Base camera reset: fast burst on BASE_TELEPORT_BUTTON (no wiggle)
  figurines_buyer_log "reset spam: point=BASE_TELEPORT_BUTTON (${base_x},${base_y}) count=${_fb_base_reset_count} delay=${_fb_base_reset_delay_ms}ms"
  figurines_buyer_trace "base camera reset ×${_fb_base_reset_count} delay=${_fb_base_reset_delay_ms}ms at (${base_x},${base_y})"
  move_mouse "$base_x" "$base_y" || return 2
  input_click_current_burst "$_fb_base_reset_count" "$_fb_base_reset_delay_ms" || return 2
  figurines_buyer_trace "wait post-base ${_fb_post_base_wait}"
  figurines_buyer_log "reset spam complete"
  input_sleep "$_fb_post_base_wait" || return 2

  # Walk forward to shop area
  figurines_buyer_log "walk W ${_fb_walk_forward_duration}"
  figurines_buyer_trace "walk W for ${_fb_walk_forward_duration}"
  keydown w || return 2
  input_sleep "$_fb_walk_forward_duration" || return 2
  keyup w || return 2

  # First diagonal: W+D to align with shop teleporter
  figurines_buyer_log "walk W+D ${_fb_first_diagonal_duration}"
  figurines_buyer_trace "diagonal W+D for ${_fb_first_diagonal_duration}"
  keydown w || return 2
  keydown d || return 2
  input_sleep "$_fb_first_diagonal_duration" || return 2
  keyup w || return 2
  keyup d || return 2

  # Wait for teleport to complete
  figurines_buyer_log "teleport wait ${_fb_teleport_wait}"
  figurines_buyer_trace "teleport wait ${_fb_teleport_wait}"
  input_sleep "$_fb_teleport_wait" || return 2

  # Second diagonal: W+D to reach shop interior
  figurines_buyer_log "walk W+D ${_fb_second_diagonal_duration}"
  figurines_buyer_trace "diagonal W+D for ${_fb_second_diagonal_duration}"
  keydown w || return 2
  keydown d || return 2
  input_sleep "$_fb_second_diagonal_duration" || return 2
  keyup w || return 2
  keyup d || return 2

  figurines_buyer_trace "wait menu-open ${_fb_menu_open_wait}"
  input_sleep "$_fb_menu_open_wait" || return 2

  # Buy all figurines
  figurines_buyer_log "buy FIGURINES_BUY_ALL (${buy_x},${buy_y})"
  figurines_buyer_trace "click buy-all at (${buy_x},${buy_y})"
  click_point "$buy_x" "$buy_y" || return 2
  figurines_buyer_trace "wait post-buy ${_fb_post_buy_wait}"
  input_sleep "$_fb_post_buy_wait" || return 2

  # Walk away left to exit
  figurines_buyer_log "walk A ${_fb_walk_away_duration}"
  figurines_buyer_trace "walk A left for ${_fb_walk_away_duration}"
  keydown a || return 2
  input_sleep "$_fb_walk_away_duration" || return 2
  keyup a || return 2

  figurines_buyer_log "complete"
  figurines_buyer_trace "run complete"
}

figurines_buyer_dry_run() {
  figurines_buyer_preflight || return 2

  local base_x base_y buy_x buy_y coords

  coords="$(figurines_buyer_get_point base_teleport)" || return 2
  base_x="${coords%% *}"; base_y="${coords##* }"

  coords="$(figurines_buyer_get_point buy_all)" || return 2
  buy_x="${coords%% *}"; buy_y="${coords##* }"

  printf 'DRY-RUN figurines-buyer\n'
  printf '  mode:                  %s\n' "$(input_mode)"
  printf '  base_teleport_button:  (%s, %s)\n' "$base_x" "$base_y"
  printf '  figurines_buy_all:     (%s, %s)\n' "$buy_x" "$buy_y"
  printf '  base_reset:            ×%s @ %sms (fast burst, no wiggle)\n' "$_fb_base_reset_count" "$_fb_base_reset_delay_ms"
  printf '  pre_reset_wait:        %s\n' "$_fb_pre_reset_wait"
  printf '  post_base_wait:        %s\n' "$_fb_post_base_wait"
  printf '  walk_forward:          W for %s\n' "$_fb_walk_forward_duration"
  printf '  first_diagonal:        W+D for %s\n' "$_fb_first_diagonal_duration"
  printf '  teleport_wait:         %s\n' "$_fb_teleport_wait"
  printf '  second_diagonal:       W+D for %s\n' "$_fb_second_diagonal_duration"
  printf '  menu_open_wait:        %s\n' "$_fb_menu_open_wait"
  printf '  post_buy_wait:         %s\n' "$_fb_post_buy_wait"
  printf '  walk_away_left:        A for %s\n' "$_fb_walk_away_duration"

  MACRO_INPUT_MODE=dry-run figurines_buyer_run || return 2
}
