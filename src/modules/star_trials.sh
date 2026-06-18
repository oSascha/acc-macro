#!/usr/bin/env bash
# Star Trials module — legacy import from background-gamescope-star-trials
# STATUS: imported / experimental / disabled
# This module is NOT wired to live orchestrator until logic is audited and
# point coordinates are calibrated for the current display/resolution.
# TODO: audit run_one_trial() against current game UI before enabling live.
# TODO: add point calibration for all 17 star trials points.
# TODO: parse_duration_ms does not support decimal seconds (e.g. 2.5) — the
#       legacy timing values use raw `sleep` calls with float seconds.

_star_trials_script="${BASH_SOURCE[0]}"
_star_trials_dir="${_star_trials_script%/*}"
if test "$_star_trials_dir" = "$_star_trials_script"; then
  _star_trials_dir="."
fi

_star_trials_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$_star_trials_project_root"; then
  _star_trials_project_root="$(cd "$_star_trials_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$_star_trials_project_root/src/lib/config.sh"
# shellcheck source=../lib/input.sh
. "$_star_trials_project_root/src/lib/input.sh"

# Runtime config handles (overridable for testing)
STAR_TRIALS_DEFAULTS_FILE="${STAR_TRIALS_DEFAULTS_FILE:-}"

# Settings (populated by star_trials_load_settings)
_st_lobby_walk_seconds=""
_st_menu_open_delay=""
_st_post_select_card_delay=""
_st_post_card_pick_delay=""
_st_post_difficulty_select_delay=""
_st_post_start_load_delay=""
_st_round_wait_seconds=""
_st_return_to_lobby_delay=""
_st_repetitions_per_difficulty=""

star_trials_trace() {
  printf 'TRACE star-trials %s\n' "$*"
}

star_trials_load_settings() {
  local runtime_dir defaults_file
  runtime_dir="$(config_star_trials_dir)"
  defaults_file="${STAR_TRIALS_DEFAULTS_FILE:-$runtime_dir/defaults.conf}"

  config_bootstrap_buyer star_trials

  if ! test -f "$defaults_file"; then
    log_error "star trials defaults not found: $defaults_file"
    return 2
  fi

  # shellcheck source=/dev/null
  . "$defaults_file"

  _st_lobby_walk_seconds="${LOBBY_WALK_SECONDS:-2.5}"
  _st_menu_open_delay="${MENU_OPEN_DELAY:-0.5}"
  _st_post_select_card_delay="${POST_SELECT_CARD_DELAY:-0.3}"
  _st_post_card_pick_delay="${POST_CARD_PICK_DELAY:-0.3}"
  _st_post_difficulty_select_delay="${POST_DIFFICULTY_SELECT_DELAY:-0.3}"
  _st_post_start_load_delay="${POST_START_LOAD_DELAY:-2.0}"
  _st_round_wait_seconds="${ROUND_WAIT_SECONDS:-85}"
  _st_return_to_lobby_delay="${RETURN_TO_LOBBY_DELAY:-2.0}"
  _st_repetitions_per_difficulty="${REPETITIONS_PER_DIFFICULTY:-3}"
}

star_trials_dry_run() {
  star_trials_load_settings || return 2

  printf 'DRY-RUN star-trials (legacy/experimental — NOT enabled for live)\n'
  printf '  status:                    imported, disabled, NOT audited for live use\n'
  printf '  lobby_walk_seconds:        %s\n' "$_st_lobby_walk_seconds"
  printf '  menu_open_delay:           %s\n' "$_st_menu_open_delay"
  printf '  post_select_card_delay:    %s\n' "$_st_post_select_card_delay"
  printf '  post_card_pick_delay:      %s\n' "$_st_post_card_pick_delay"
  printf '  post_difficulty_delay:     %s\n' "$_st_post_difficulty_select_delay"
  printf '  post_start_load_delay:     %s\n' "$_st_post_start_load_delay"
  printf '  round_wait_seconds:        %s\n' "$_st_round_wait_seconds"
  printf '  return_to_lobby_delay:     %s\n' "$_st_return_to_lobby_delay"
  printf '  repetitions_per_diff:      %s\n' "$_st_repetitions_per_difficulty"
  printf '\n'
  printf '  planned sequence per difficulty:\n'
  printf '    1. walk W for %ss to lobby marker\n' "$_st_lobby_walk_seconds"
  printf '    2. click SELECT_CARD  (point: not yet calibrated)\n'
  printf '    3. click CARD_N       (point: not yet calibrated)\n'
  printf '    4. click DIFFICULTY   (point: not yet calibrated)\n'
  printf '    5. click START\n'
  printf '    6. wait post-start-load: %ss\n' "$_st_post_start_load_delay"
  printf '    7. click AFK anchor   (point: not yet calibrated)\n'
  printf '    8. wait round: %ss\n' "$_st_round_wait_seconds"
  printf '    9. wait return: %ss\n' "$_st_return_to_lobby_delay"
  printf '    repeat ×%s per difficulty\n' "$_st_repetitions_per_difficulty"
  printf '\n'
  printf '  NOTE: timing values use decimal seconds — parse_duration_ms does not\n'
  printf '        support these; raw sleep() calls will be needed in live logic.\n'
  printf '  NOTE: 17 point coordinates not yet calibrated.\n'
  printf '  NOTE: no live input sent in dry-run.\n'
}

star_trials_run() {
  log_error "Star Trials is not enabled yet — needs point calibration and logic audit before live use"
  return 2
}
