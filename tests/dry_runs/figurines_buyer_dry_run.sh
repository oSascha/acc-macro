#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s missing %s\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    return 1
  fi

  printf 'PASS: %s contains %s\n' "$label" "$needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'FAIL: %s unexpectedly contained %s\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    return 1
  fi

  printf 'PASS: %s does not contain %s\n' "$label" "$needle"
}

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input allowance must not be enabled for this dry-run test\n' >&2
  exit 1
fi
printf 'PASS: live input allowance is not enabled\n'

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/defaults.conf" <<'EOF'
BASE_CAMERA_RESET_COUNT=10
BASE_CAMERA_RESET_DELAY=15ms
PRE_RESET_WAIT=50ms
POST_BASE_WAIT=250ms
WALK_FORWARD_DURATION=1s300ms
FIRST_DIAGONAL_DURATION=1s500ms
TELEPORT_WAIT=1s
SECOND_DIAGONAL_DURATION=1s500ms
MENU_OPEN_WAIT=200ms
POST_BUY_WAIT=700ms
WALK_AWAY_LEFT_DURATION=600ms
EOF

cat > "$tmp_dir/points.conf" <<'EOF'
BASE_TELEPORT_BUTTON_X=150
BASE_TELEPORT_BUTTON_Y=250
FIGURINES_BUY_ALL_X=350
FIGURINES_BUY_ALL_Y=450
EOF

run_dry() {
  MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  FIGURINES_BUYER_DEFAULTS_FILE="$tmp_dir/defaults.conf" \
  FIGURINES_BUYER_POINTS_FILE="$tmp_dir/points.conf" \
    bash -c '. "$1/src/modules/figurines_buyer.sh" && figurines_buyer_dry_run' _ "$project_root" 2>&1
}

output="$(run_dry)"
assert_contains "$output" "DRY-RUN figurines-buyer" "dry-run header"
assert_contains "$output" "base_teleport_button:  (150, 250)" "base teleport point"
assert_contains "$output" "figurines_buy_all:     (350, 450)" "buy all point"
assert_contains "$output" "base_reset:            ×10 @ 15ms (fast burst, no wiggle)" "base reset settings"
assert_contains "$output" "pre_reset_wait:        50ms" "pre reset wait setting"
assert_contains "$output" "walk_forward:          W for 1s300ms" "walk forward (old handoff value)"
assert_contains "$output" "first_diagonal:        W+D for 1s500ms" "first diagonal"
assert_contains "$output" "teleport_wait:         1s" "teleport wait"
assert_contains "$output" "second_diagonal:       W+D for 1s500ms" "second diagonal"
assert_contains "$output" "menu_open_wait:        200ms" "menu open wait (old handoff value)"
assert_contains "$output" "post_buy_wait:         700ms" "post buy wait (old handoff value)"
assert_contains "$output" "walk_away_left:        A for 600ms" "walk away (old handoff value)"
assert_contains "$output" "figurines-buyer pre-reset wait 50ms" "pre-reset wait log"
assert_contains "$output" "figurines-buyer reset spam: point=BASE_TELEPORT_BUTTON" "reset spam log"
assert_contains "$output" "count=10 delay=15ms" "reset spam count/delay"
assert_contains "$output" "figurines-buyer reset spam complete" "reset spam complete log"
assert_contains "$output" "figurines-buyer walk W 1s300ms" "walk log"
assert_contains "$output" "figurines-buyer buy FIGURINES_BUY_ALL" "buy log"
assert_contains "$output" "figurines-buyer complete" "complete log"
assert_contains "$output" "TRACE figurines-buyer run start" "run trace start"
assert_contains "$output" "TRACE input dry-run" "dry-run input trace"
assert_contains "$output" "TRACE figurines-buyer run complete" "run trace complete"
assert_contains "$output" "TRACE input dry-run DISPLAY=" "dry-run xdotool trace prefix"
assert_not_contains "$output" "ERROR" "no error"

printf '\nAll figurines buyer dry-run tests passed.\n'
