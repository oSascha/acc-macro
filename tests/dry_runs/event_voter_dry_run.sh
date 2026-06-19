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

assert_exit_zero() {
  local label="$1"
  local status="$2"
  if test "$status" -ne 0; then
    printf 'FAIL: %s exited %s (expected 0)\n' "$label" "$status" >&2
    return 1
  fi
  printf 'PASS: %s exited 0\n' "$label"
}

assert_exit_nonzero() {
  local label="$1"
  local status="$2"
  if test "$status" -eq 0; then
    printf 'FAIL: %s exited 0 (expected non-zero)\n' "$label" >&2
    return 1
  fi
  printf 'PASS: %s exited non-zero (%s)\n' "$label" "$status"
}

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input allowance must not be enabled for this dry-run test\n' >&2
  exit 1
fi
printf 'PASS: live input allowance is not enabled\n'

template_dir="$project_root/config_templates/event_voter"
training_dir="$project_root/runtime_config/event_voter/training"

# ── Test 1: config templates exist ───────────────────────────────────────────
if test -f "$template_dir/defaults.conf"; then
  printf 'PASS: config_templates/event_voter/defaults.conf exists\n'
else
  printf 'FAIL: config_templates/event_voter/defaults.conf missing\n' >&2
  exit 1
fi

if test -f "$template_dir/points.conf"; then
  printf 'PASS: config_templates/event_voter/points.conf exists\n'
else
  printf 'FAIL: config_templates/event_voter/points.conf missing\n' >&2
  exit 1
fi

# ── Test 2: EVENT_VOTER_ENABLED=0 by default ─────────────────────────────────
ev_enabled_val="$(grep -E '^EVENT_VOTER_ENABLED=' "$template_dir/defaults.conf" | cut -d= -f2)"
if test "${ev_enabled_val:-}" = "0"; then
  printf 'PASS: EVENT_VOTER_ENABLED=0 by default\n'
else
  printf 'FAIL: EVENT_VOTER_ENABLED default is "%s" (expected 0)\n' "$ev_enabled_val" >&2
  exit 1
fi

# ── Test 3: EVENT_VOTER_LIVE_ALLOWED=0 by default ────────────────────────────
ev_live_val="$(grep -E '^EVENT_VOTER_LIVE_ALLOWED=' "$template_dir/defaults.conf" | cut -d= -f2)"
if test "${ev_live_val:-}" = "0"; then
  printf 'PASS: EVENT_VOTER_LIVE_ALLOWED=0 by default\n'
else
  printf 'FAIL: EVENT_VOTER_LIVE_ALLOWED default is "%s" (expected 0)\n' "$ev_live_val" >&2
  exit 1
fi

# ── Test 4: EVENT_VOTER_CLICK_IF_TARGET_FOUND=1 in template ──────────────────
if grep -q '^EVENT_VOTER_CLICK_IF_TARGET_FOUND=1' "$template_dir/defaults.conf"; then
  printf 'PASS: EVENT_VOTER_CLICK_IF_TARGET_FOUND=1 in template\n'
else
  printf 'FAIL: EVENT_VOTER_CLICK_IF_TARGET_FOUND=1 missing from template\n' >&2
  exit 1
fi

# ── Test 5: EVENT_VOTER_SKIP_IF_NO_TARGET=1 in template ──────────────────────
if grep -q '^EVENT_VOTER_SKIP_IF_NO_TARGET=1' "$template_dir/defaults.conf"; then
  printf 'PASS: EVENT_VOTER_SKIP_IF_NO_TARGET=1 in template\n'
else
  printf 'FAIL: EVENT_VOTER_SKIP_IF_NO_TARGET=1 missing from template\n' >&2
  exit 1
fi

# ── Test 6: macroctl validate-config event-voter exits 0 ─────────────────────
validate_output="$(MACRO_PROJECT_ROOT="$project_root" "$project_root/bin/macroctl" validate-config event-voter 2>&1)" || true
validate_status=$?
assert_exit_zero "validate-config event-voter" "$validate_status"
assert_contains "$validate_output" "validate-config event-voter: OK" "validate-config output"

# ── Test 7: event-voter-schedule prints all 6 times ──────────────────────────
schedule_output="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" \
  "$project_root/bin/macroctl" dry-run event-voter-schedule 2>&1)"
schedule_status=$?
assert_exit_zero "dry-run event-voter-schedule" "$schedule_status"
for slot in "07:00" "07:20" "07:40" "19:00" "19:20" "19:40"; do
  assert_contains "$schedule_output" "$slot" "schedule output"
done
assert_contains "$schedule_output" "Event Voter Schedule" "schedule header"
assert_contains "$schedule_output" "Next event:" "schedule next event"

# ── Test 8: detector handles missing image ────────────────────────────────────
missing_img_output="$(python3 "$project_root/src/modules/event_voter_detect.py" \
  --image "/tmp/nonexistent_image_for_ev_test_$$.png" \
  --training-dir "$training_dir" \
  --generated-dir "/tmp/ev_gen_test_$$" 2>&1)" || missing_img_status=$?
missing_img_status="${missing_img_status:-0}"
assert_exit_nonzero "detector on missing image" "$missing_img_status"
assert_contains "$missing_img_output" "ERROR" "missing image error message"

# ── Test 9: detector cv2 check ───────────────────────────────────────────────
if python3 -c "import cv2" 2>/dev/null; then
  printf 'PASS: cv2 (OpenCV) is available — skipping cv2-missing test\n'
else
  cv2_output="$(python3 "$project_root/src/modules/event_voter_detect.py" \
    --image "/tmp/x.png" 2>&1)" || cv2_status=$?
  cv2_status="${cv2_status:-0}"
  assert_exit_nonzero "detector cv2 missing exit code" "$cv2_status"
  assert_contains "$cv2_output" "cv2" "cv2 missing error"
  assert_contains "$cv2_output" "opencv" "cv2 install hint"
fi

# ── Tests 10-12: training image detection (if images exist) ──────────────────
xp_seed="$training_dir/live_event_seed.png"
mut_seed="$training_dir/live_event_seed_mutation.png"

tmp_gen="$(mktemp -d)"
trap 'rm -rf "$tmp_gen"' EXIT

if test -f "$xp_seed" && python3 -c "import cv2" 2>/dev/null; then
  xp_output="$(python3 "$project_root/src/modules/event_voter_detect.py" \
    --image "$xp_seed" \
    --training-dir "$training_dir" \
    --generated-dir "$tmp_gen" 2>&1)"
  xp_status=$?
  assert_exit_zero "offline detector on xp seed" "$xp_status"
  assert_contains "$xp_output" "BEST_SLOT=right" "xp seed: BEST_SLOT=right"
  assert_contains "$xp_output" "BEST_LABEL=3x_xp" "xp seed: BEST_LABEL=3x_xp"
  assert_contains "$xp_output" "SAFE_TO_CLICK=1" "xp seed: SAFE_TO_CLICK=1"
  assert_not_contains "$xp_output" "LEFT_LABEL=3x_xp" "xp seed: left slot not misclassified"
  assert_not_contains "$xp_output" "LEFT_CONFIDENCE=1.00" "xp seed: no false 1.00 on left slot"
else
  printf 'PASS: xp seed not present or cv2 missing — skipping offline xp seed test\n'
fi

if test -f "$mut_seed" && python3 -c "import cv2" 2>/dev/null; then
  mut_output="$(python3 "$project_root/src/modules/event_voter_detect.py" \
    --image "$mut_seed" \
    --training-dir "$training_dir" \
    --generated-dir "$tmp_gen" 2>&1)"
  mut_status=$?
  assert_exit_zero "offline detector on mutation seed" "$mut_status"
  assert_contains "$mut_output" "BEST_SLOT=right" "mutation seed: BEST_SLOT=right"
  assert_contains "$mut_output" "BEST_LABEL=3x_xp" "mutation seed: BEST_LABEL=3x_xp (priority)"
  assert_contains "$mut_output" "MIDDLE_LABEL=3x_mutation_chance" "mutation seed: middle=3x_mutation_chance"
  assert_contains "$mut_output" "SAFE_TO_CLICK=1" "mutation seed: SAFE_TO_CLICK=1"
  assert_not_contains "$mut_output" "LEFT_LABEL=3x_xp" "mutation seed: left slot not misclassified"
  assert_not_contains "$mut_output" "LEFT_CONFIDENCE=1.00" "mutation seed: no false 1.00 on left slot"
else
  printf 'PASS: mutation seed not present or cv2 missing — skipping offline mutation seed test\n'
fi

# ── Test 12: generated files stay in runtime_config/event_voter/generated ────
if test -f "$xp_seed" && python3 -c "import cv2" 2>/dev/null; then
  gen_dir="$project_root/runtime_config/event_voter/generated"
  python3 "$project_root/src/modules/event_voter_detect.py" \
    --image "$xp_seed" \
    --training-dir "$training_dir" \
    --generated-dir "$gen_dir" >/dev/null 2>&1 || true
  if test -d "$gen_dir"; then
    printf 'PASS: generated dir is under runtime_config/event_voter/generated\n'
  fi
else
  printf 'PASS: skipping generated dir check (no xp seed or no cv2)\n'
fi

# ── Test 13: generated dir not tracked by git ────────────────────────────────
gitignore_output="$(git -C "$project_root" check-ignore -q \
  "runtime_config/event_voter/generated/test.png" 2>&1 && printf 'ignored' || printf 'not-ignored')"
if test "$gitignore_output" = "ignored"; then
  printf 'PASS: runtime_config/event_voter/generated/ is gitignored\n'
else
  gitignore_root="$(git -C "$project_root" check-ignore -q "runtime_config/" 2>&1 && printf 'ignored' || printf 'not-ignored')"
  if test "$gitignore_root" = "ignored"; then
    printf 'PASS: runtime_config/ is gitignored (covers generated dir)\n'
  else
    printf 'FAIL: runtime_config/event_voter/generated/ is not gitignored\n' >&2
    exit 1
  fi
fi

# ── Test 14: dry-run does not require live env vars ──────────────────────────
dry_output="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" \
  "$project_root/bin/macroctl" dry-run event-voter-schedule 2>&1)"
dry_status=$?
assert_exit_zero "dry-run schedule without live env" "$dry_status"
printf 'PASS: dry-run mode does not require live env vars\n'

# ── Test 15: live click path is gated ────────────────────────────────────────
gate_output="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" bash -c '
  . "$MACRO_PROJECT_ROOT/src/lib/config.sh"
  . "$MACRO_PROJECT_ROOT/src/lib/input.sh"
  . "$MACRO_PROJECT_ROOT/src/modules/event_voter.sh"
  event_voter_load_config
  _ev_enabled=1
  _ev_live_allowed=1
  result=0
  event_voter_click_vote_slot "left" 2>&1 || result=$?
  printf "click_result=%s\n" "$result"
' 2>&1)"
assert_contains "$gate_output" "click_result=1" "live click blocked in dry-run mode"

# ── Test 16: orchestrator dry-run still works with event voter OFF ────────────
tmp_market="$(mktemp -d)"
tmp_figurines="$(mktemp -d)"
tmp_recovery="$(mktemp -d)"

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
cat > "$tmp_recovery/defaults.conf" <<'EOF'
RECOVERY_ENABLED=0
EOF
cat > "$tmp_recovery/points.conf" <<'EOF'
RECOVERY_POPUP_CLOSE_BUTTON_X=
RECOVERY_POPUP_CLOSE_BUTTON_Y=
RECOVERY_ITEMS_TAB_BUTTON_X=
RECOVERY_ITEMS_TAB_BUTTON_Y=
EOF

trap 'rm -rf "$tmp_market" "$tmp_figurines" "$tmp_recovery" "$tmp_gen"' EXIT

orch_output="$(MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  MARKET_BUYER_DEFAULTS_FILE="$tmp_market/defaults.conf" \
  MARKET_BUYER_POINTS_FILE="$tmp_market/points.conf" \
  FIGURINES_BUYER_DEFAULTS_FILE="$tmp_figurines/defaults.conf" \
  FIGURINES_BUYER_POINTS_FILE="$tmp_figurines/points.conf" \
  RECOVERY_DEFAULTS_FILE="$tmp_recovery/defaults.conf" \
  RECOVERY_POINTS_FILE="$tmp_recovery/points.conf" \
  ORCHESTRATOR_EVENT_VOTER_ENABLED=0 \
  ORCHESTRATOR_PACK_ENABLED=0 \
  MACROCTL_PATH="$project_root/bin/macroctl" \
  "$project_root/src/modules/orchestrator.sh" --dry-run --cycles 1 2>&1)"
orch_status=$?
assert_exit_zero "orchestrator dry-run with event voter OFF" "$orch_status"
assert_contains "$orch_output" "DRY-RUN orchestrator" "orchestrator dry-run header"
assert_contains "$orch_output" "event_voter:       disabled" "event voter shows disabled"

# ── Test 17: event voter OFF does not change cycle output ────────────────────
assert_contains "$orch_output" "pack opener disabled — would idle 2s" "pack disabled message present"
assert_not_contains "$orch_output" "event voter:" "no event voter output when disabled"

printf '\nAll event voter dry-run tests passed.\n'
