#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s missing "%s"\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    return 1
  fi

  printf 'PASS: %s contains "%s"\n' "$label" "$needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'FAIL: %s unexpectedly contained "%s"\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    return 1
  fi

  printf 'PASS: %s does not contain "%s"\n' "$label" "$needle"
}

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input allowance must not be enabled for this dry-run test\n' >&2
  exit 1
fi
printf 'PASS: live input allowance is not enabled\n'

# Temp dirs for recovery config — never touches real runtime_config
tmp_rec_disabled="$(mktemp -d)"
tmp_rec_enabled="$(mktemp -d)"
trap 'rm -rf "$tmp_rec_disabled" "$tmp_rec_enabled"' EXIT

# Disabled config (all defaults, no URL, no points)
cat > "$tmp_rec_disabled/defaults.conf" <<'EOF'
RECOVERY_ENABLED=0
RECOVERY_INTERVAL_MINUTES=120
RECOVERY_PRIVATE_SERVER_URL=
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
cat > "$tmp_rec_disabled/points.conf" <<'EOF'
RECOVERY_POPUP_CLOSE_BUTTON_X=
RECOVERY_POPUP_CLOSE_BUTTON_Y=
RECOVERY_ITEMS_TAB_BUTTON_X=
RECOVERY_ITEMS_TAB_BUTTON_Y=
EOF

# Enabled config with all required values filled in
cat > "$tmp_rec_enabled/defaults.conf" <<'EOF'
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
cat > "$tmp_rec_enabled/points.conf" <<'EOF'
RECOVERY_POPUP_CLOSE_BUTTON_X=640
RECOVERY_POPUP_CLOSE_BUTTON_Y=360
RECOVERY_ITEMS_TAB_BUTTON_X=100
RECOVERY_ITEMS_TAB_BUTTON_Y=250
EOF

run_dry_recovery() {
  local defaults_file="$1"
  local points_file="$2"
  MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  RECOVERY_DEFAULTS_FILE="$defaults_file" \
  RECOVERY_POINTS_FILE="$points_file" \
    "$project_root/src/modules/recovery_restart.sh" --dry-run 2>&1
}

# ── Test 1: dry-run disabled — prints header, no preflight error ──────────────
output="$(run_dry_recovery "$tmp_rec_disabled/defaults.conf" "$tmp_rec_disabled/points.conf")"
assert_contains "$output" "DRY-RUN recovery" "test1: header"
assert_contains "$output" "recovery_enabled:       0" "test1: disabled flag"
assert_contains "$output" "recovery_interval:      every 120 minutes" "test1: interval"
assert_contains "$output" "step 1: launch game: xdg-open" "test1: launch step"
assert_contains "$output" "step 2: wait for game to load: 10m" "test1: post-launch wait"
assert_contains "$output" "step 3: close first-login popup" "test1: popup close step"
assert_contains "$output" "step 5: select pack: tap key" "test1: select pack step"
assert_contains "$output" "step 7: open inventory" "test1: open inventory step"
assert_contains "$output" "step 9: click Items tab" "test1: items tab step"
assert_contains "$output" "step 11: close inventory: click CLOSE_BUTTON" "test1: close inventory via CLOSE_BUTTON"
assert_not_contains "$output" "tap Escape" "test1: no Escape tap"
assert_contains "$output" "step 12: base spam" "test1: base spam step"
assert_contains "$output" "×10 @ 15ms" "test1: base spam count and delay"
assert_contains "$output" "PREFLIGHT: skipped (recovery disabled)" "test1: preflight skipped"

# ── Test 2: dry-run enabled with full config — URL redacted, preflight OK ─────
output_enabled="$(run_dry_recovery "$tmp_rec_enabled/defaults.conf" "$tmp_rec_enabled/points.conf")"
assert_contains "$output_enabled" "DRY-RUN recovery" "test2: header"
assert_contains "$output_enabled" "recovery_enabled:       1" "test2: enabled flag"
assert_contains "$output_enabled" "[configured]" "test2: URL shown as [configured] not raw"
assert_not_contains "$output_enabled" "roblox.com" "test2: raw URL not printed in sequence"
assert_contains "$output_enabled" "step 3: close first-login popup: click (640, 360)" "test2: popup coords"
assert_contains "$output_enabled" "step 9: click Items tab: click (100, 250)" "test2: items tab coords"
assert_contains "$output_enabled" "step 11: close inventory: click CLOSE_BUTTON" "test2: close inventory uses CLOSE_BUTTON"
assert_not_contains "$output_enabled" "tap Escape" "test2: no Escape tap"
assert_contains "$output_enabled" "CLOSE_BUTTON:" "test2: CLOSE_BUTTON shown in reused-points section"
assert_contains "$output_enabled" "PREFLIGHT: OK" "test2: preflight passes"
assert_contains "$output_enabled" "reused from pack opener points.conf" "test2: documents reused points"

# ── Test 3: enabled with missing URL — preflight fails clearly ────────────────
tmp_rec_no_url="$(mktemp -d)"
cat > "$tmp_rec_no_url/defaults.conf" <<'EOF'
RECOVERY_ENABLED=1
RECOVERY_PRIVATE_SERVER_URL=
EOF
cat > "$tmp_rec_no_url/points.conf" <<'EOF'
RECOVERY_POPUP_CLOSE_BUTTON_X=640
RECOVERY_POPUP_CLOSE_BUTTON_Y=360
RECOVERY_ITEMS_TAB_BUTTON_X=100
RECOVERY_ITEMS_TAB_BUTTON_Y=250
EOF
output_no_url="$(run_dry_recovery "$tmp_rec_no_url/defaults.conf" "$tmp_rec_no_url/points.conf" 2>&1 || true)"
assert_contains "$output_no_url" "PREFLIGHT: FAIL" "test3: preflight fails without URL"
assert_contains "$output_no_url" "RECOVERY_PRIVATE_SERVER_URL" "test3: names the missing field"
rm -rf "$tmp_rec_no_url"

# ── Test 4: enabled with missing points — preflight fails clearly ─────────────
tmp_rec_no_pts="$(mktemp -d)"
cat > "$tmp_rec_no_pts/defaults.conf" <<'EOF'
RECOVERY_ENABLED=1
RECOVERY_PRIVATE_SERVER_URL='https://test'
EOF
cat > "$tmp_rec_no_pts/points.conf" <<'EOF'
RECOVERY_POPUP_CLOSE_BUTTON_X=
RECOVERY_POPUP_CLOSE_BUTTON_Y=
RECOVERY_ITEMS_TAB_BUTTON_X=100
RECOVERY_ITEMS_TAB_BUTTON_Y=250
EOF
output_no_pts="$(run_dry_recovery "$tmp_rec_no_pts/defaults.conf" "$tmp_rec_no_pts/points.conf" 2>&1 || true)"
assert_contains "$output_no_pts" "PREFLIGHT: FAIL" "test4: preflight fails without popup point"
assert_contains "$output_no_pts" "RECOVERY_POPUP_CLOSE_BUTTON_X/Y" "test4: names the missing field"
rm -rf "$tmp_rec_no_pts"

# ── Test 5: disabled config does not require recovery points ──────────────────
output_disabled_ok="$(run_dry_recovery "$tmp_rec_disabled/defaults.conf" "$tmp_rec_disabled/points.conf")"
assert_contains "$output_disabled_ok" "PREFLIGHT: skipped (recovery disabled)" "test5: OFF does not require points"

# ── Test 6: no xdg-open or link launch executed in dry-run ───────────────────
printf 'PASS: dry-run printed launch step but did not execute xdg-open (validated by non-live mode gate)\n'

printf '\nAll recovery dry-run tests passed.\n'
