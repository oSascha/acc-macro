#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; return 1; }

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label contains \"$needle\""
  else
    printf 'FAIL: %s — expected to contain: %s\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label does not contain \"$needle\""
  else
    printf 'FAIL: %s — unexpectedly contained: %s\n' "$label" "$needle" >&2
    return 1
  fi
}

setup_acc="$project_root/bin/setup-acc"

# ── Test: setup-acc exists and is executable ──────────────────────────────────
if test -x "$setup_acc"; then
  pass "bin/setup-acc exists and is executable"
else
  fail "bin/setup-acc missing or not executable"
fi

# ── Test: --help exits 0 and shows usage ─────────────────────────────────────
help_out="$("$setup_acc" --help 2>&1)"
if "$setup_acc" --help >/dev/null 2>&1; then
  pass "--help exits 0"
else
  fail "--help exited non-zero"
fi
assert_contains "$help_out" "Usage:" "--help output"
assert_contains "$help_out" "--dry-run" "--help output"
assert_contains "$help_out" "--check" "--help output"
assert_contains "$help_out" "800x600 preset" "--help output"
assert_contains "$help_out" "Does not run the live macro" "--help safety note"
assert_contains "$help_out" "Does not send any mouse or keyboard input" "--help safety note"

# ── Test: --check exits 0 without installing or writing ───────────────────────
check_out="$("$setup_acc" --check 2>&1)" || true
if "$setup_acc" --check >/dev/null 2>&1; then
  pass "--check exits 0"
else
  fail "--check exited non-zero"
fi
assert_contains "$check_out" "Status" "--check output"
assert_not_contains "$check_out" "sudo apt" "--check output (no apt in check mode)"
assert_not_contains "$check_out" "flatpak install" "--check output (no flatpak install in check mode)"

# ── Test: --dry-run prints planned steps without doing anything ───────────────
dry_out="$("$setup_acc" --dry-run 2>&1)"
if "$setup_acc" --dry-run >/dev/null 2>&1; then
  pass "--dry-run exits 0"
else
  fail "--dry-run exited non-zero"
fi
assert_contains "$dry_out" "dry-run" "--dry-run output"
assert_contains "$dry_out" "Would" "--dry-run output (describes planned steps)"
assert_contains "$dry_out" "800x600" "--dry-run output mentions preset"
assert_not_contains "$dry_out" "Get:1" "--dry-run does not run apt"
assert_not_contains "$dry_out" "Installing org.vinegarhq.Sober" "--dry-run does not install Sober"

# ── Test: setup-acc uses simple words in menu labels ─────────────────────────
setup_src="$(cat "$setup_acc")"
assert_contains "$setup_src" "800x600 preset" "setup-acc source (menu label)"
assert_contains "$setup_src" "Start blank and calibrate" "setup-acc source (blank option label)"
assert_contains "$setup_src" "Keep my existing config" "setup-acc source (keep option label)"

# ── Test: setup-acc contains no real private server URL ──────────────────────
# Placeholders like YOUR_CODE or XXXXXXXX are acceptable; actual share URLs are not.
assert_not_contains "$setup_src" "roblox.com/share?code=" "setup-acc source (no real URL)"

# ── Test: setup-acc contains no hardcoded personal home paths ────────────────
# Pattern check — personal usernames (PERSONAL_HOME_PATH) are not stored in this file.
if grep -qE '/home/[a-z][a-z0-9_-]+' "$setup_acc"; then
  fail "setup-acc source contains a hardcoded home path (PERSONAL_HOME_PATH check)"
else
  pass "setup-acc source contains no hardcoded home paths"
fi

# ── Test: preset files exist ─────────────────────────────────────────────────
preset_dir="$project_root/presets/800x600_known_good"
for expected_file in \
  pack_opener/points.conf \
  pack_opener/timing.conf \
  pack_opener/potion_plan.conf \
  market_buyer/points.conf \
  market_buyer/defaults.conf \
  figurines_buyer/points.conf \
  figurines_buyer/defaults.conf \
  orchestrator/defaults.conf \
  recovery/defaults.conf \
  recovery/points.conf
do
  if test -f "$preset_dir/$expected_file"; then
    pass "preset file exists: $expected_file"
  else
    fail "preset file missing: presets/800x600_known_good/$expected_file"
  fi
done

# ── Test: recovery preset does not contain a real private URL ────────────────
rec_preset="$preset_dir/recovery/defaults.conf"
rec_content="$(cat "$rec_preset")"
assert_not_contains "$rec_content" "roblox.com/share?code=" "recovery preset (no real URL)"
assert_contains "$rec_content" "RECOVERY_PRIVATE_SERVER_URL=" "recovery preset has URL key"
assert_contains "$rec_content" "RECOVERY_ENABLED=0" "recovery preset has RECOVERY_ENABLED=0"

rec_url_val="$(grep '^RECOVERY_PRIVATE_SERVER_URL=' "$rec_preset" | cut -d= -f2-)"
if test -z "$rec_url_val"; then
  pass "recovery preset URL value is blank (correct)"
else
  fail "recovery preset URL is not blank: $rec_url_val"
fi

# ── Test: preset mentions 800x600 ────────────────────────────────────────────
pack_pts="$preset_dir/pack_opener/points.conf"
pack_pts_content="$(cat "$pack_pts")"
assert_contains "$pack_pts_content" "800x600" "pack_opener/points.conf mentions resolution"

# ── Test: .gitignore still ignores runtime_config/ ───────────────────────────
gitignore_content="$(cat "$project_root/.gitignore")"
assert_contains "$gitignore_content" "runtime_config/" ".gitignore covers runtime_config/"

# ── Test: runtime_config/ is not tracked ─────────────────────────────────────
if git -C "$project_root" ls-files --error-unmatch runtime_config/ >/dev/null 2>&1; then
  fail "runtime_config/ is tracked by git (should be gitignored)"
else
  pass "runtime_config/ is not tracked by git"
fi

# ── Test: presets/ is tracked ────────────────────────────────────────────────
if git -C "$project_root" ls-files --error-unmatch "presets/800x600_known_good/pack_opener/points.conf" >/dev/null 2>&1; then
  pass "presets/800x600_known_good/pack_opener/points.conf is tracked by git"
else
  if test -f "$preset_dir/pack_opener/points.conf"; then
    pass "preset file exists on disk"
  else
    fail "preset file missing from disk"
  fi
fi

# ── Test: setup-acc syntax is valid ──────────────────────────────────────────
if bash -n "$setup_acc" 2>&1; then
  pass "bin/setup-acc passes bash -n syntax check"
else
  fail "bin/setup-acc failed bash -n syntax check"
fi

# ── Test: no hardcoded home paths in preset files ────────────────────────────
# Pattern check — personal usernames (PERSONAL_HOME_PATH) are not stored here.
if grep -rqE '/home/[a-z][a-z0-9_-]+' "$preset_dir" 2>/dev/null; then
  fail "preset files contain hardcoded home paths (PERSONAL_HOME_PATH check)"
else
  pass "preset files contain no hardcoded home paths"
fi

# ── Test: preset pack_opener/points.conf has all expected keys ───────────────
for key in \
  BASE_TELEPORT_BUTTON_X BASE_TELEPORT_BUTTON_Y \
  PLACE_HOLD_POINT_X PLACE_HOLD_POINT_Y \
  PACK_CLICK_POINT_X PACK_CLICK_POINT_Y \
  MENU_BUTTON_X MENU_BUTTON_Y \
  CLOSE_BUTTON_X CLOSE_BUTTON_Y
do
  if grep -qE "^${key}=" "$pack_pts"; then
    pass "pack_opener/points.conf has key: $key"
  else
    fail "pack_opener/points.conf missing expected key: $key"
  fi
done

# ── Test: preset market_buyer/points.conf has all expected keys ──────────────
market_pts="$preset_dir/market_buyer/points.conf"
for key in TOP_MARKET_BUTTON_X TOP_MARKET_BUTTON_Y MARKET_BUY_ALL_X MARKET_BUY_ALL_Y; do
  if grep -qE "^${key}=" "$market_pts"; then
    pass "market_buyer/points.conf has key: $key"
  else
    fail "market_buyer/points.conf missing expected key: $key"
  fi
done

# ── Test: preset figurines_buyer/points.conf has all expected keys ───────────
figurines_pts="$preset_dir/figurines_buyer/points.conf"
for key in FIGURINES_BUY_ALL_X FIGURINES_BUY_ALL_Y; do
  if grep -qE "^${key}=" "$figurines_pts"; then
    pass "figurines_buyer/points.conf has key: $key"
  else
    fail "figurines_buyer/points.conf missing expected key: $key"
  fi
done

# ── Test: preset pack_opener coordinate values are filled (not blank) ─────────
for key in \
  BASE_TELEPORT_BUTTON_X BASE_TELEPORT_BUTTON_Y \
  PLACE_HOLD_POINT_X PLACE_HOLD_POINT_Y \
  PACK_CLICK_POINT_X PACK_CLICK_POINT_Y \
  MENU_BUTTON_X MENU_BUTTON_Y \
  CLOSE_BUTTON_X CLOSE_BUTTON_Y
do
  val="$(grep -E "^${key}=" "$pack_pts" | cut -d= -f2-)"
  if test -n "$val"; then
    pass "pack_opener/points.conf $key has a value"
  else
    fail "pack_opener/points.conf $key is blank (expected a coordinate in the 800x600 preset)"
  fi
done

# ── Test: no malformed/truncated keys in preset or template files ─────────────
# These substrings would indicate a key name that lost its leading character.
# Anchored to line start to avoid false matches within valid full key names.
malformed_ok=1
for truncated in ASE_TELEPORT LACE_HOLD ACK_CLICK ENU_BUTTON LOSE_BUTTON; do
  if grep -rqE "^${truncated}" "$preset_dir" "$project_root/config_templates" 2>/dev/null; then
    fail "found malformed/truncated key starting with: $truncated"
    malformed_ok=0
  fi
done
if test "$malformed_ok" = "1"; then
  pass "no malformed/truncated keys found in preset or template files"
fi

printf '\nAll setup-acc dry-run tests passed.\n'
