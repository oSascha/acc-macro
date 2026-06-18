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

# Temp configs for buyer and recovery modules so preflight passes
tmp_market="$(mktemp -d)"
tmp_figurines="$(mktemp -d)"
tmp_orch="$(mktemp -d)"
tmp_recovery="$(mktemp -d)"
trap 'rm -rf "$tmp_market" "$tmp_figurines" "$tmp_orch" "$tmp_recovery"' EXIT

cat > "$tmp_market/defaults.conf" <<'EOF'
BASE_CAMERA_RESET_COUNT=10
BASE_CAMERA_RESET_DELAY=15ms
POST_BASE_WAIT=300ms
WALK_FORWARD_DURATION=1s200ms
MENU_OPEN_WAIT=500ms
POST_BUY_WAIT=500ms
WALK_BACK_DURATION=800ms
EOF
cat > "$tmp_market/points.conf" <<'EOF'
TOP_MARKET_BUTTON_X=100
TOP_MARKET_BUTTON_Y=200
MARKET_BUY_ALL_X=300
MARKET_BUY_ALL_Y=400
EOF

cat > "$tmp_figurines/defaults.conf" <<'EOF'
BASE_CAMERA_RESET_COUNT=10
BASE_CAMERA_RESET_DELAY=15ms
POST_BASE_WAIT=250ms
WALK_FORWARD_DURATION=1s300ms
FIRST_DIAGONAL_DURATION=1s500ms
TELEPORT_WAIT=1s
SECOND_DIAGONAL_DURATION=1s500ms
MENU_OPEN_WAIT=200ms
POST_BUY_WAIT=700ms
WALK_AWAY_LEFT_DURATION=600ms
EOF
cat > "$tmp_figurines/points.conf" <<'EOF'
BASE_TELEPORT_BUTTON_X=150
BASE_TELEPORT_BUTTON_Y=250
FIGURINES_BUY_ALL_X=350
FIGURINES_BUY_ALL_Y=450
EOF

cat > "$tmp_orch/defaults.conf" <<'EOF'
REFRESH_INTERVAL_MINUTES=10
PACK_OPENER_ENABLED=1
MARKET_BUYER_ENABLED=1
FIGURINES_BUYER_ENABLED=1
STAR_TRIALS_ENABLED=0
EOF

# Recovery disabled config (default)
cat > "$tmp_recovery/defaults.conf" <<'EOF'
RECOVERY_ENABLED=0
RECOVERY_INTERVAL_MINUTES=120
RECOVERY_PRIVATE_SERVER_URL=
RECOVERY_POST_LAUNCH_WAIT=10m
RECOVERY_POST_POPUP_CLOSE_WAIT=500ms
RECOVERY_SELECT_PACK_KEY=1
RECOVERY_POST_SELECT_PACK_WAIT=500ms
RECOVERY_OPEN_INVENTORY_WAIT=500ms
RECOVERY_POST_ITEMS_TAB_WAIT=500ms
RECOVERY_PRE_RESUME_BASE_SPAM_COUNT=10
RECOVERY_PRE_RESUME_BASE_SPAM_DELAY=15ms
RECOVERY_POST_BASE_SPAM_WAIT=50ms
EOF
cat > "$tmp_recovery/points.conf" <<'EOF'
RECOVERY_POPUP_CLOSE_BUTTON_X=
RECOVERY_POPUP_CLOSE_BUTTON_Y=
RECOVERY_ITEMS_TAB_BUTTON_X=
RECOVERY_ITEMS_TAB_BUTTON_Y=
EOF

run_dry() {
  MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  MARKET_BUYER_DEFAULTS_FILE="$tmp_market/defaults.conf" \
  MARKET_BUYER_POINTS_FILE="$tmp_market/points.conf" \
  FIGURINES_BUYER_DEFAULTS_FILE="$tmp_figurines/defaults.conf" \
  FIGURINES_BUYER_POINTS_FILE="$tmp_figurines/points.conf" \
  RECOVERY_DEFAULTS_FILE="$tmp_recovery/defaults.conf" \
  RECOVERY_POINTS_FILE="$tmp_recovery/points.conf" \
  MACROCTL_PATH="$project_root/bin/macroctl" \
    "$project_root/src/modules/orchestrator.sh" --dry-run "$@" 2>&1
}

run_dry_with_toggles() {
  MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  MARKET_BUYER_DEFAULTS_FILE="$tmp_market/defaults.conf" \
  MARKET_BUYER_POINTS_FILE="$tmp_market/points.conf" \
  FIGURINES_BUYER_DEFAULTS_FILE="$tmp_figurines/defaults.conf" \
  FIGURINES_BUYER_POINTS_FILE="$tmp_figurines/points.conf" \
  RECOVERY_DEFAULTS_FILE="$tmp_recovery/defaults.conf" \
  RECOVERY_POINTS_FILE="$tmp_recovery/points.conf" \
  MACROCTL_PATH="$project_root/bin/macroctl" \
  ORCHESTRATOR_PACK_ENABLED="${1:-1}" \
  ORCHESTRATOR_MARKET_BUYER_ENABLED="${2:-1}" \
  ORCHESTRATOR_FIGURINES_BUYER_ENABLED="${3:-1}" \
    "$project_root/src/modules/orchestrator.sh" --dry-run --cycles 1 2>&1
}

# Test 1: all enabled, default 3 cycles, recovery disabled (default)
output="$(run_dry --cycles 1)"
assert_contains "$output" "DRY-RUN orchestrator" "orchestrator header"
assert_contains "$output" "pack_opener:       enabled" "pack enabled"
assert_contains "$output" "market_buyer:      enabled" "market enabled"
assert_contains "$output" "figurines_buyer:   enabled" "figurines enabled"
assert_contains "$output" "recovery_restart:  disabled" "recovery disabled by default"
assert_contains "$output" "buyer_schedule:    every 10 minutes" "buyer schedule"
assert_contains "$output" "buyer_order:       Market Buyer" "buyer order"
assert_contains "$output" "simulating buyer run at 10-min boundary" "buyer run simulation"
assert_contains "$output" "DRY-RUN market-buyer" "market buyer dry run"
assert_contains "$output" "DRY-RUN figurines-buyer" "figurines buyer dry run"
assert_contains "$output" "[simulating pack cycle" "pack cycle simulation"
assert_contains "$output" "DRY-RUN orchestrator complete" "complete message"
assert_contains "$output" "TRACE input dry-run DISPLAY=" "dry-run xdotool trace prefix"
assert_not_contains "$output" "simulating recovery restart" "no recovery sim when disabled"

# Test 2: market buyer disabled
output_no_market="$(run_dry_with_toggles 1 0 1)"
assert_contains "$output_no_market" "market_buyer:      disabled" "market disabled"
assert_contains "$output_no_market" "figurines_buyer:   enabled" "figurines still enabled"
assert_not_contains "$output_no_market" "DRY-RUN market-buyer" "market-buyer not run"
assert_contains "$output_no_market" "DRY-RUN figurines-buyer" "figurines-buyer still runs"

# Test 3: figurines buyer disabled
output_no_fig="$(run_dry_with_toggles 1 1 0)"
assert_contains "$output_no_fig" "figurines_buyer:   disabled" "figurines disabled"
assert_contains "$output_no_fig" "DRY-RUN market-buyer" "market-buyer still runs"
assert_not_contains "$output_no_fig" "DRY-RUN figurines-buyer" "figurines-buyer not run"

# Test 4: pack disabled, buyers still run
output_no_pack="$(run_dry_with_toggles 0 1 1)"
assert_contains "$output_no_pack" "pack_opener:       disabled" "pack disabled"
assert_contains "$output_no_pack" "pack opener disabled — would idle 2s" "idle message"
assert_not_contains "$output_no_pack" "simulating pack cycle" "no pack cycle"

# Test 5: all disabled must fail
all_disabled_output="$(run_dry_with_toggles 0 0 0 2>&1 || true)"
assert_contains "$all_disabled_output" "all modules disabled" "all disabled error"

# ── Recovery tests ────────────────────────────────────────────────────────────

# Create a fully-configured recovery config for enabled tests
tmp_recovery_enabled="$(mktemp -d)"
trap 'rm -rf "$tmp_market" "$tmp_figurines" "$tmp_orch" "$tmp_recovery" "$tmp_recovery_enabled"' EXIT

cat > "$tmp_recovery_enabled/defaults.conf" <<'EOF'
RECOVERY_ENABLED=1
RECOVERY_INTERVAL_MINUTES=120
RECOVERY_PRIVATE_SERVER_URL='https://www.roblox.com/share?code=test&type=Server'
RECOVERY_LAUNCH_COMMAND=xdg-open
RECOVERY_KILL_SOBER_BEFORE_RELAUNCH=0
RECOVERY_POST_LAUNCH_WAIT=10m
RECOVERY_POST_POPUP_CLOSE_WAIT=500ms
RECOVERY_SELECT_PACK_KEY=1
RECOVERY_POST_SELECT_PACK_WAIT=500ms
RECOVERY_OPEN_INVENTORY_WAIT=500ms
RECOVERY_POST_ITEMS_TAB_WAIT=500ms
RECOVERY_PRE_RESUME_BASE_SPAM_COUNT=10
RECOVERY_PRE_RESUME_BASE_SPAM_DELAY=15ms
RECOVERY_POST_BASE_SPAM_WAIT=50ms
EOF
cat > "$tmp_recovery_enabled/points.conf" <<'EOF'
RECOVERY_POPUP_CLOSE_BUTTON_X=640
RECOVERY_POPUP_CLOSE_BUTTON_Y=360
RECOVERY_ITEMS_TAB_BUTTON_X=100
RECOVERY_ITEMS_TAB_BUTTON_Y=250
EOF

run_dry_with_recovery() {
  MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  MARKET_BUYER_DEFAULTS_FILE="$tmp_market/defaults.conf" \
  MARKET_BUYER_POINTS_FILE="$tmp_market/points.conf" \
  FIGURINES_BUYER_DEFAULTS_FILE="$tmp_figurines/defaults.conf" \
  FIGURINES_BUYER_POINTS_FILE="$tmp_figurines/points.conf" \
  RECOVERY_DEFAULTS_FILE="$tmp_recovery_enabled/defaults.conf" \
  RECOVERY_POINTS_FILE="$tmp_recovery_enabled/points.conf" \
  MACROCTL_PATH="$project_root/bin/macroctl" \
  ORCHESTRATOR_RECOVERY_ENABLED=1 \
    "$project_root/src/modules/orchestrator.sh" --dry-run --cycles 1 2>&1
}

# Test 6: orchestrator dry-run with recovery disabled — no recovery sim
output_rec_off="$(run_dry --cycles 1)"
assert_contains "$output_rec_off" "recovery_restart:  disabled" "test6: recovery disabled label"
assert_not_contains "$output_rec_off" "simulating recovery restart" "test6: no recovery sim when disabled"
assert_not_contains "$output_rec_off" "DRY-RUN recovery" "test6: no recovery dry-run output"

# Test 7: orchestrator dry-run with recovery enabled — simulates recovery
output_rec_on="$(run_dry_with_recovery)"
assert_contains "$output_rec_on" "recovery_restart:  enabled" "test7: recovery enabled label"
assert_contains "$output_rec_on" "simulating recovery restart at interval boundary" "test7: recovery sim runs"
assert_contains "$output_rec_on" "DRY-RUN recovery" "test7: recovery dry-run output"
assert_contains "$output_rec_on" "step 1: launch game:" "test7: launch step shown"
assert_contains "$output_rec_on" "step 2: wait for game to load: 10m" "test7: post-launch wait shown"
assert_contains "$output_rec_on" "[configured]" "test7: URL redacted in dry-run"
assert_not_contains "$output_rec_on" "roblox.com" "test7: raw URL not printed"
assert_contains "$output_rec_on" "PREFLIGHT: OK" "test7: recovery preflight passes"

# Test 8: recovery OFF does not block normal macro start (no preflight failure)
output_rec_off_clean="$(run_dry --cycles 1)"
assert_not_contains "$output_rec_off_clean" "preflight failed" "test8: recovery OFF does not block start"

printf '\nAll orchestrator dry-run tests passed.\n'
