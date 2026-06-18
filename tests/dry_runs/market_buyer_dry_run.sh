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

# Write test configs to a temp dir so we don't mutate runtime_config
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/defaults.conf" <<'EOF'
BASE_CAMERA_RESET_COUNT=10
BASE_CAMERA_RESET_DELAY=15ms
PRE_RESET_WAIT=50ms
POST_BASE_WAIT=300ms
WALK_FORWARD_DURATION=1s200ms
MENU_OPEN_WAIT=500ms
POST_BUY_WAIT=500ms
WALK_BACK_DURATION=800ms
EOF

cat > "$tmp_dir/points.conf" <<'EOF'
TOP_MARKET_BUTTON_X=100
TOP_MARKET_BUTTON_Y=200
MARKET_BUY_ALL_X=300
MARKET_BUY_ALL_Y=400
EOF

run_dry() {
  MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  MARKET_BUYER_DEFAULTS_FILE="$tmp_dir/defaults.conf" \
  MARKET_BUYER_POINTS_FILE="$tmp_dir/points.conf" \
    bash -c '. "$1/src/modules/market_buyer.sh" && market_buyer_dry_run' _ "$project_root" 2>&1
}

output="$(run_dry)"
assert_contains "$output" "DRY-RUN market-buyer" "dry-run header"
assert_contains "$output" "top_market_button:  (100, 200)" "top market point"
assert_contains "$output" "buy_all:            (300, 400)" "buy all point"
assert_contains "$output" "base_reset:         ×10 @ 15ms (fast burst, no wiggle)" "base reset settings"
assert_contains "$output" "pre_reset_wait:     50ms" "pre reset wait setting"
assert_contains "$output" "post_base_wait:     300ms" "post base wait"
assert_contains "$output" "walk_forward:       W for 1s200ms" "walk forward duration"
assert_contains "$output" "walk_back:          S for 800ms" "walk back duration"
assert_contains "$output" "market-buyer pre-reset wait 50ms" "pre-reset wait log"
assert_contains "$output" "market-buyer reset spam: point=TOP_MARKET_BUTTON" "reset spam log"
assert_contains "$output" "count=10 delay=15ms" "reset spam count/delay"
assert_contains "$output" "market-buyer reset spam complete" "reset spam complete log"
assert_contains "$output" "market-buyer walk W 1s200ms" "walk log"
assert_contains "$output" "market-buyer buy MARKET_BUY_ALL" "buy log"
assert_contains "$output" "market-buyer complete" "complete log"
assert_contains "$output" "TRACE market-buyer run start" "run trace start"
assert_contains "$output" "TRACE input dry-run" "dry-run input trace"
assert_contains "$output" "TRACE market-buyer run complete" "run trace complete"
assert_contains "$output" "TRACE input dry-run DISPLAY=" "dry-run xdotool trace prefix"
assert_not_contains "$output" "ERROR" "no error"

printf '\nAll market buyer dry-run tests passed.\n'
