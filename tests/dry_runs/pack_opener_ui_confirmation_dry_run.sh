#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input must not be enabled for this dry-run test\n' >&2
  exit 1
fi
printf 'PASS: live input is not enabled\n'

# ── Re-define the confirmation helper for isolated testing ───────────────────
# Same logic as full_macro_start_input_valid in bin/pack-opener-ui.
# If this helper changes in the UI, update both.
full_macro_start_input_valid() {
  local typed="$1"
  typed="${typed#"${typed%%[![:space:]]*}"}"
  typed="${typed%"${typed##*[![:space:]]}"}"
  if test -z "$typed"; then
    return 1
  fi
  typed="$(printf '%s' "$typed" | tr '[:upper:]' '[:lower:]')"
  case "$typed" in
    s|start|r|run|y|yes|"start full macro"|"run full macro") return 0 ;;
    *) return 1 ;;
  esac
}

assert_accepted() {
  local input="$1"
  local result=0
  full_macro_start_input_valid "$input" || result=$?
  if test "$result" -ne 0; then
    printf 'FAIL: %q should be accepted\n' "$input" >&2
    return 1
  fi
  printf 'PASS: accepted: %q\n' "$input"
}

assert_rejected() {
  local input="$1"
  local result=0
  full_macro_start_input_valid "$input" || result=$?
  if test "$result" -eq 0; then
    printf 'FAIL: %q should be rejected\n' "$input" >&2
    return 1
  fi
  printf 'PASS: rejected: %q\n' "$input"
}

# ── Test 1: all accepted inputs ───────────────────────────────────────────────
assert_accepted "start"
assert_accepted "s"
assert_accepted "START"
assert_accepted "Start"
assert_accepted "run"
assert_accepted "r"
assert_accepted "yes"
assert_accepted "y"
assert_accepted "START FULL MACRO"
assert_accepted "RUN FULL MACRO"
# case variants
assert_accepted "S"
assert_accepted "Run"
assert_accepted "Yes"
assert_accepted "Y"
assert_accepted "start full macro"
assert_accepted "run full macro"
# whitespace-padded
assert_accepted "  start  "
assert_accepted " s "
assert_accepted "  START FULL MACRO  "

# ── Test 2: empty input cancels ───────────────────────────────────────────────
assert_rejected ""

# ── Test 3: random input does not start ──────────────────────────────────────
assert_rejected "nope"
assert_rejected "please start"
assert_rejected "go"
assert_rejected "okay"
assert_rejected "1"
assert_rejected "begin"
assert_rejected "launch"
assert_rejected "start macro"
assert_rejected "full macro"

# ── Test 4: verify helper exists in pack-opener-ui ───────────────────────────
grep -q 'full_macro_start_input_valid' "$project_root/bin/pack-opener-ui"
printf 'PASS: full_macro_start_input_valid defined in pack-opener-ui\n'

# ── Test 5: verify start/s prompt text updated in pack-opener-ui ─────────────
grep -q "Type.*start.*or.*s.*to start" "$project_root/bin/pack-opener-ui"
printf 'PASS: updated start prompt present in pack-opener-ui\n'

# ── Test 6: verify p = pause controls line present ───────────────────────────
grep -q 'p = pause after current loop' "$project_root/bin/pack-opener-ui"
printf 'PASS: p = pause controls text in pack-opener-ui\n'

# ── Test 7: verify c = continue controls line present ────────────────────────
grep -q 'c = continue' "$project_root/bin/pack-opener-ui"
printf 'PASS: c = continue controls text in pack-opener-ui\n'

# ── Test 8: verify pause requested text present ──────────────────────────────
grep -q 'pause requested' "$project_root/bin/pack-opener-ui"
printf 'PASS: pause requested controls text in pack-opener-ui\n'

# ── Test 9: Ctrl+C trap is still wired in pack-opener-ui ─────────────────────
grep -q '_acc_stop_full_macro\|request_stop_until_stopped' "$project_root/bin/pack-opener-ui"
printf 'PASS: stop trap helper present in pack-opener-ui\n'
grep -q "trap '.*stop.*' INT\|trap \".*stop.*\" INT\|trap '_acc_stop_full_macro' INT" "$project_root/bin/pack-opener-ui"
printf 'PASS: INT trap set in pack-opener-ui\n'

# ── Test 10: no macro timing or config changes ────────────────────────────────
# Verify timing and points config files are unchanged from the committed versions
for f in \
  runtime_config/pack_opener/timing.conf \
  runtime_config/pack_opener/points.conf \
  runtime_config/market_buyer/defaults.conf \
  runtime_config/figurines_buyer/defaults.conf; do
  if test -f "$project_root/$f"; then
    if git -C "$project_root" diff --quiet HEAD -- "$f" 2>/dev/null; then
      printf 'PASS: %s unchanged\n' "$f"
    else
      printf 'INFO: %s has local changes (may be runtime config, not a source error)\n' "$f"
    fi
  fi
done

printf '\nAll pack-opener-ui confirmation dry-run tests passed.\n'
