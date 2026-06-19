#!/usr/bin/env bash

_event_voter_script="${BASH_SOURCE[0]}"
_event_voter_dir="${_event_voter_script%/*}"
if test "$_event_voter_dir" = "$_event_voter_script"; then
  _event_voter_dir="."
fi

_event_voter_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$_event_voter_project_root"; then
  _event_voter_project_root="$(cd "$_event_voter_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$_event_voter_project_root/src/lib/config.sh"
# shellcheck source=../lib/input.sh
. "$_event_voter_project_root/src/lib/input.sh"

_ev_enabled="0"
_ev_live_allowed="0"
_ev_timezone="Europe/Amsterdam"
_ev_times="07:00,07:20,07:40,19:00,19:20,19:40"
_ev_pre_hold="25"
_ev_scan_window="25"
_ev_screenshot_interval_ms="500"
_ev_min_confidence="0.55"
_ev_require_consensus="1"
_ev_max_frames="8"
_ev_priority="3x_xp,3x_mutation_chance"
_ev_click_if_found="1"
_ev_skip_if_no_target="1"
_ev_log_results="1"
_ev_left_x=""
_ev_left_y=""
_ev_middle_x=""
_ev_middle_y=""
_ev_right_x=""
_ev_right_y=""

event_voter_load_config() {
  local runtime_dir defaults_file points_file template_dir
  runtime_dir="$(config_event_voter_dir)"
  defaults_file="$runtime_dir/defaults.conf"
  points_file="$runtime_dir/points.conf"

  mkdir -p "$runtime_dir"
  template_dir="$(config_event_voter_template_dir)"

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

  _ev_enabled="${EVENT_VOTER_ENABLED:-0}"
  _ev_live_allowed="${EVENT_VOTER_LIVE_ALLOWED:-0}"
  _ev_timezone="${EVENT_VOTER_TIMEZONE:-Europe/Amsterdam}"
  _ev_times="${EVENT_VOTER_TIMES:-07:00,07:20,07:40,19:00,19:20,19:40}"
  _ev_pre_hold="${EVENT_VOTER_PRE_HOLD_SECONDS:-25}"
  _ev_scan_window="${EVENT_VOTER_SCAN_WINDOW_SECONDS:-25}"
  _ev_screenshot_interval_ms="${EVENT_VOTER_SCREENSHOT_INTERVAL_MS:-500}"
  _ev_min_confidence="${EVENT_VOTER_MIN_CONFIDENCE:-0.55}"
  _ev_require_consensus="${EVENT_VOTER_REQUIRE_CONSENSUS_FRAMES:-1}"
  _ev_max_frames="${EVENT_VOTER_MAX_FRAMES:-8}"
  _ev_priority="${EVENT_VOTER_PRIORITY:-3x_xp,3x_mutation_chance}"
  _ev_click_if_found="${EVENT_VOTER_CLICK_IF_TARGET_FOUND:-1}"
  _ev_skip_if_no_target="${EVENT_VOTER_SKIP_IF_NO_TARGET:-1}"
  _ev_log_results="${EVENT_VOTER_LOG_RESULTS:-1}"
  _ev_left_x="${EVENT_OPTION_LEFT_X:-}"
  _ev_left_y="${EVENT_OPTION_LEFT_Y:-}"
  _ev_middle_x="${EVENT_OPTION_MIDDLE_X:-}"
  _ev_middle_y="${EVENT_OPTION_MIDDLE_Y:-}"
  _ev_right_x="${EVENT_OPTION_RIGHT_X:-}"
  _ev_right_y="${EVENT_OPTION_RIGHT_Y:-}"
}

event_voter_preflight() {
  local training_dir
  training_dir="$(config_event_voter_dir)/training"

  if ! test -d "$training_dir"; then
    printf 'event voter: training dir missing: %s\n' "$training_dir" >&2
    printf 'event voter: add training screenshots: live_event_seed.png and/or live_event_seed_mutation.png\n' >&2
    return 1
  fi

  local found_any=0
  if test -f "$training_dir/live_event_seed.png" || test -f "$training_dir/live_event_seed_xp.png"; then
    found_any=1
  fi
  if test -f "$training_dir/live_event_seed_mutation.png"; then
    found_any=1
  fi

  if test "$found_any" = "0"; then
    printf 'event voter: no training images found in %s\n' "$training_dir" >&2
    printf 'event voter: add: live_event_seed.png and/or live_event_seed_mutation.png\n' >&2
    return 1
  fi

  if ! python3 -c "import cv2" 2>/dev/null; then
    printf 'event voter: cv2 (OpenCV) not available\n' >&2
    printf 'event voter: install with: sudo dnf install python3-opencv\n' >&2
    printf 'event voter:           or: pip install opencv-python-headless\n' >&2
    return 2
  fi

  return 0
}

_ev_parse_hhmm_to_seconds() {
  local hhmm="$1"
  local h m
  h="${hhmm%%:*}"
  m="${hhmm##*:}"
  printf '%d' $(( 10#$h * 3600 + 10#$m * 60 ))
}

event_voter_next_event_info() {
  local now_s slot_s diff best_diff best_slot best_is_tomorrow
  local tz_now
  tz_now="$(TZ="$_ev_timezone" date '+%H:%M:%S')"
  local now_h now_m now_sec
  now_h="${tz_now%%:*}"
  now_m="${tz_now#*:}"; now_m="${now_m%%:*}"
  now_sec="${tz_now##*:}"
  now_s=$(( 10#$now_h * 3600 + 10#$now_m * 60 + 10#$now_sec ))

  best_diff=999999
  best_slot=""
  best_is_tomorrow=0

  local slot is_tomorrow
  local IFS_SAVE="$IFS"
  IFS=","
  for slot in $_ev_times; do
    IFS="$IFS_SAVE"
    slot_s="$(_ev_parse_hhmm_to_seconds "$slot")"
    diff=$(( slot_s - now_s ))
    is_tomorrow=0
    if test "$diff" -lt 0; then
      diff=$(( diff + 86400 ))
      is_tomorrow=1
    fi
    if test "$diff" -lt "$best_diff"; then
      best_diff="$diff"
      best_slot="$slot"
      best_is_tomorrow="$is_tomorrow"
    fi
    IFS=","
  done
  IFS="$IFS_SAVE"

  local best_date
  if test "$best_is_tomorrow" = "1"; then
    best_date="$(TZ="$_ev_timezone" date -d 'tomorrow' '+%Y-%m-%d' 2>/dev/null \
      || TZ="$_ev_timezone" date -v+1d '+%Y-%m-%d' 2>/dev/null || true)"
  else
    best_date="$(TZ="$_ev_timezone" date '+%Y-%m-%d')"
  fi

  printf 'NEXT_EVENT_TS=%s %s\n' "$best_date" "$best_slot"
  printf 'NEXT_EVENT_SLOT=%s\n' "$best_slot"
  printf 'SECONDS_UNTIL=%s\n' "$best_diff"
}

event_voter_should_hold_now() {
  local info secs
  info="$(event_voter_next_event_info)"
  secs="$(printf '%s\n' "$info" | grep '^SECONDS_UNTIL=' | cut -d= -f2)"
  if test -z "$secs"; then
    return 1
  fi
  if test "$secs" -le "$_ev_pre_hold" && test "$secs" -gt 0; then
    return 0
  fi
  return 1
}

event_voter_due_now() {
  local now_s slot_s diff
  local tz_now
  tz_now="$(TZ="$_ev_timezone" date '+%H:%M:%S')"
  local now_h now_m now_sec
  now_h="${tz_now%%:*}"
  now_m="${tz_now#*:}"; now_m="${now_m%%:*}"
  now_sec="${tz_now##*:}"
  now_s=$(( 10#$now_h * 3600 + 10#$now_m * 60 + 10#$now_sec ))

  local slot
  local IFS_SAVE="$IFS"
  IFS=","
  for slot in $_ev_times; do
    IFS="$IFS_SAVE"
    slot_s="$(_ev_parse_hhmm_to_seconds "$slot")"
    diff=$(( now_s - slot_s ))
    if test "$diff" -ge 0 && test "$diff" -le "$_ev_scan_window"; then
      return 0
    fi
    IFS=","
  done
  IFS="$IFS_SAVE"
  return 1
}

_ev_detector_path() {
  printf '%s/src/modules/event_voter_detect.py\n' "$_event_voter_project_root"
}

_ev_training_dir() {
  printf '%s/training\n' "$(config_event_voter_dir)"
}

_ev_generated_dir() {
  printf '%s/generated\n' "$(config_event_voter_dir)"
}

event_voter_run_offline_image() {
  local image_path="${1:-}"
  shift || true
  local extra_args="$*"

  if test -z "$image_path"; then
    printf 'event voter: --image is required\n' >&2
    return 1
  fi

  python3 "$(_ev_detector_path)" \
    --image "$image_path" \
    --training-dir "$(_ev_training_dir)" \
    --generated-dir "$(_ev_generated_dir)" \
    --min-confidence "$_ev_min_confidence" \
    --mode offline \
    ${extra_args:+$extra_args}
}

_ev_take_screenshot() {
  local out_path="$1"
  if command -v import >/dev/null 2>&1; then
    import -window root "$out_path" 2>/dev/null
  elif command -v scrot >/dev/null 2>&1; then
    scrot "$out_path" 2>/dev/null
  else
    printf 'event voter: no screenshot tool available (need import or scrot)\n' >&2
    return 1
  fi
}

event_voter_run_live_window() {
  if test "${MACRO_INPUT_MODE:-dry-run}" = "dry-run"; then
    printf 'event voter: dry-run mode — skipping live window\n'
    return 0
  fi

  local frame=0
  local match_count=0
  local best_slot="none"
  local best_label="unknown"
  local best_conf="0.00"
  local tmp_dir runtime_dir
  runtime_dir="$(config_event_voter_dir)"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  local interval_s
  interval_s="$(awk "BEGIN{printf \"%.3f\", $_ev_screenshot_interval_ms / 1000}")"

  while test "$frame" -lt "$_ev_max_frames"; do
    frame=$(( frame + 1 ))
    local shot_path="$tmp_dir/frame_${frame}.png"

    if ! _ev_take_screenshot "$shot_path"; then
      break
    fi

    local det_output safe slot label conf
    det_output="$(python3 "$(_ev_detector_path)" \
      --image "$shot_path" \
      --training-dir "$(_ev_training_dir)" \
      --generated-dir "$(_ev_generated_dir)" \
      --min-confidence "$_ev_min_confidence" \
      --mode live 2>/dev/null || true)"

    safe="$(printf '%s\n' "$det_output" | grep '^SAFE_TO_CLICK=' | cut -d= -f2)"
    slot="$(printf '%s\n' "$det_output" | grep '^BEST_SLOT=' | cut -d= -f2)"
    label="$(printf '%s\n' "$det_output" | grep '^BEST_LABEL=' | cut -d= -f2)"
    conf="$(printf '%s\n' "$det_output" | grep '^BEST_CONFIDENCE=' | cut -d= -f2)"

    if test "${safe:-0}" = "1" && test "${slot:-none}" != "none"; then
      match_count=$(( match_count + 1 ))
      best_slot="$slot"
      best_label="$label"
      best_conf="$conf"
    fi

    if test "$match_count" -ge "$_ev_require_consensus"; then
      break
    fi

    sleep "$interval_s" 2>/dev/null || true
  done

  local action="skipped"
  if test "$match_count" -ge "$_ev_require_consensus" && test "$_ev_click_if_found" = "1"; then
    if event_voter_click_vote_slot "$best_slot"; then
      action="clicked"
    else
      action="click_blocked"
    fi
  elif test "$best_slot" = "none" && test "$_ev_skip_if_no_target" = "1"; then
    action="no_target"
  fi

  if test "$_ev_log_results" = "1"; then
    event_voter_log_result "$best_slot" "$best_label" "$best_conf" "$action"
  fi
}

event_voter_click_vote_slot() {
  local slot="${1:-none}"

  if test "$_ev_enabled" != "1"; then
    return 1
  fi
  if test "$_ev_live_allowed" != "1"; then
    return 1
  fi
  if test "${MACRO_INPUT_MODE:-dry-run}" != "live"; then
    return 1
  fi
  if test "${MACRO_LIVE_INPUT_ALLOWED:-}" != "1"; then
    return 1
  fi
  if test "$slot" = "none" || test -z "$slot"; then
    return 1
  fi

  local cx cy
  case "$slot" in
    left)
      cx="$_ev_left_x"
      cy="$_ev_left_y"
      ;;
    middle)
      cx="$_ev_middle_x"
      cy="$_ev_middle_y"
      ;;
    right)
      cx="$_ev_right_x"
      cy="$_ev_right_y"
      ;;
    *)
      return 1
      ;;
  esac

  if test -z "$cx" || test -z "$cy"; then
    printf 'event voter: click point for slot %s not configured\n' "$slot" >&2
    return 1
  fi

  input_click_at "$cx" "$cy"
}

event_voter_log_result() {
  local slot="${1:-none}"
  local label="${2:-unknown}"
  local conf="${3:-0.00}"
  local action="${4:-skipped}"
  local ts runtime_dir results_file

  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  runtime_dir="$(config_event_voter_dir)"
  results_file="$runtime_dir/results.tsv"

  mkdir -p "$runtime_dir"
  printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$slot" "$label" "$conf" "$action" >> "$results_file"
}

event_voter_print_schedule() {
  local tz="$_ev_timezone"
  local today tomorrow
  today="$(TZ="$tz" date '+%Y-%m-%d')"
  tomorrow="$(TZ="$tz" date -d 'tomorrow' '+%Y-%m-%d' 2>/dev/null \
    || TZ="$tz" date -v+1d '+%Y-%m-%d' 2>/dev/null || true)"

  local abbr
  abbr="$(TZ="$tz" date '+%Z')"

  printf 'Event Voter Schedule (%s)\n' "$tz"
  printf 'Times: %s\n' "$(printf '%s\n' "$_ev_times" | tr ',' ' ' | sed 's/ /, /g')"
  printf 'Today:\n'
  local slot
  local IFS_SAVE="$IFS"
  IFS=","
  for slot in $_ev_times; do
    IFS="$IFS_SAVE"
    printf '  %s %s %s\n' "$today" "$slot" "$abbr"
    IFS=","
  done
  IFS="$IFS_SAVE"

  if test -n "$tomorrow"; then
    printf 'Tomorrow:\n'
    IFS=","
    for slot in $_ev_times; do
      IFS="$IFS_SAVE"
      printf '  %s %s %s\n' "$tomorrow" "$slot" "$abbr"
      IFS=","
    done
    IFS="$IFS_SAVE"
  fi

  local info secs next_slot next_ts
  info="$(event_voter_next_event_info)"
  secs="$(printf '%s\n' "$info" | grep '^SECONDS_UNTIL=' | cut -d= -f2)"
  next_slot="$(printf '%s\n' "$info" | grep '^NEXT_EVENT_SLOT=' | cut -d= -f2)"
  next_ts="$(printf '%s\n' "$info" | grep '^NEXT_EVENT_TS=' | cut -d= -f2)"

  if test -n "$next_slot" && test -n "$secs"; then
    local mins
    mins=$(( secs / 60 ))
    printf 'Next event: %s %s (in %s minutes)\n' "$next_ts" "$abbr" "$mins"
  fi
}

event_voter_validate_config() {
  local ev_dir template_dir
  ev_dir="$(config_event_voter_dir)"
  template_dir="$(config_event_voter_template_dir)"

  printf 'Event Voter config dir: %s\n' "$ev_dir"
  printf 'Event Voter template dir: %s\n' "$template_dir"

  for f in defaults.conf points.conf; do
    if ! test -f "$template_dir/$f"; then
      printf 'ERROR: event voter template not found: %s/%s\n' "$template_dir" "$f" >&2
      return 2
    fi
    printf 'Template %s: OK\n' "$f"
  done

  if test -f "$ev_dir/defaults.conf"; then
    local ev_enabled_val
    ev_enabled_val="$(grep -E '^EVENT_VOTER_ENABLED=' "$ev_dir/defaults.conf" | tail -n1 | cut -d= -f2 || true)"
    printf 'Runtime defaults: found (EVENT_VOTER_ENABLED=%s)\n' "${ev_enabled_val:-0}"
  else
    printf 'Runtime defaults: not yet bootstrapped (will be created on first use)\n'
  fi

  if test -f "$ev_dir/points.conf"; then
    printf 'Runtime points: found\n'
  else
    printf 'Runtime points: not yet bootstrapped (will be created on first use)\n'
  fi

  local training_dir="$ev_dir/training"
  if test -d "$training_dir"; then
    printf 'Training dir: found\n'
    for img in live_event_seed.png live_event_seed_mutation.png; do
      if test -f "$training_dir/$img"; then
        printf '  %s: found\n' "$img"
      else
        printf '  %s: missing (add to enable detection)\n' "$img"
      fi
    done
  else
    printf 'Training dir: not found (create %s and add training images)\n' "$training_dir"
  fi

  printf 'validate-config event-voter: OK\n'
}
