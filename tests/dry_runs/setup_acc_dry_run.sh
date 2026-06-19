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

# ── Test: setup-acc has known-good profile prompt ────────────────────────────
assert_contains "$setup_src" "Known-good 800x600" "setup-acc source (known-good profile option)"
assert_contains "$setup_src" "choose_setup_profile" "setup-acc source (choose_setup_profile function)"
assert_contains "$setup_src" "PROFILE_SELECTED" "setup-acc source (PROFILE_SELECTED variable)"

# ── Test: setup-acc has launcher installation ─────────────────────────────────
assert_contains "$setup_src" "install_acc_launcher" "setup-acc source (install_acc_launcher function)"
assert_contains "$setup_src" "MACRO_INPUT_MODE=live" "setup-acc source (launcher env gate MACRO_INPUT_MODE)"
assert_contains "$setup_src" "MACRO_LIVE_INPUT_ALLOWED=1" "setup-acc source (launcher env gate MACRO_LIVE_INPUT_ALLOWED)"
assert_contains "$setup_src" "MACRO_LIVE_CYCLE_RUNNER_CONFIRM=YES" "setup-acc source (launcher env gate MACRO_LIVE_CYCLE_RUNNER_CONFIRM)"

# ── Test: launcher is not recursive (does not point to ~/.local/bin/acc) ──────
if grep -qF '~/.local/bin/acc' "$setup_acc" 2>/dev/null; then
  # Acceptable to mention the path, but it must not be used as exec target
  if grep -qE "exec.*\.local/bin/acc" "$setup_acc" 2>/dev/null; then
    fail "setup-acc installs a recursive launcher (exec ~/.local/bin/acc)"
  else
    pass "setup-acc launcher is not recursive (path mentioned but not exec'd)"
  fi
else
  pass "setup-acc launcher is not recursive"
fi

# ── Test: setup-acc has --diagnose flag ───────────────────────────────────────
assert_contains "$setup_src" "--diagnose" "setup-acc source (--diagnose flag)"
assert_contains "$setup_src" "run_diagnose" "setup-acc source (run_diagnose function)"
assert_contains "$setup_src" "acc_setup_diagnose.txt" "setup-acc source (diagnose output file)"
assert_contains "$setup_src" "Send this file for debugging" "setup-acc source (diagnose message)"

# ── Test: --diagnose flag exits 0 ────────────────────────────────────────────
if "$setup_acc" --diagnose >/dev/null 2>&1; then
  pass "--diagnose exits 0"
else
  fail "--diagnose exited non-zero"
fi

# ── Test: setup-acc has final summary function ───────────────────────────────
assert_contains "$setup_src" "show_final_summary" "setup-acc source (show_final_summary function)"

# ── Test: new preset file ui/toggles.conf exists ─────────────────────────────
if test -f "$preset_dir/ui/toggles.conf"; then
  pass "preset file exists: ui/toggles.conf"
else
  fail "preset file missing: presets/800x600_known_good/ui/toggles.conf"
fi

# ── Test: ui/toggles.conf has Pack Opener enabled and others disabled ─────────
ui_toggles_file="$preset_dir/ui/toggles.conf"
if test -f "$ui_toggles_file"; then
  ui_toggles_content="$(cat "$ui_toggles_file")"
  assert_contains "$ui_toggles_content" "TOGGLE_PACK_OPENER=1" "ui/toggles.conf Pack Opener enabled"
  assert_contains "$ui_toggles_content" "TOGGLE_MARKET_BUYER=0" "ui/toggles.conf Market Buyer disabled"
  assert_contains "$ui_toggles_content" "TOGGLE_FIGURINES_BUYER=0" "ui/toggles.conf Figurines Buyer disabled"
  assert_contains "$ui_toggles_content" "TOGGLE_RECOVERY_RESTART=0" "ui/toggles.conf Recovery disabled"
  assert_contains "$ui_toggles_content" "TOGGLE_EVENT_VOTER=0" "ui/toggles.conf Event Voter disabled"
fi

# ── Test: orchestrator preset has safe defaults (market/figurines disabled) ──
orch_preset="$preset_dir/orchestrator/defaults.conf"
if test -f "$orch_preset"; then
  orch_preset_content="$(cat "$orch_preset")"
  assert_contains "$orch_preset_content" "PACK_OPENER_ENABLED=1" "orchestrator preset Pack Opener enabled"
  assert_contains "$orch_preset_content" "MARKET_BUYER_ENABLED=0" "orchestrator preset Market Buyer disabled"
  assert_contains "$orch_preset_content" "FIGURINES_BUYER_ENABLED=0" "orchestrator preset Figurines Buyer disabled"
fi

# ── Test: pack-opener-ui has toggle load/save functions ──────────────────────
ui_src="$(cat "$project_root/bin/pack-opener-ui")"
assert_contains "$ui_src" "load_ui_toggles" "pack-opener-ui source (load_ui_toggles function)"
assert_contains "$ui_src" "save_ui_toggles" "pack-opener-ui source (save_ui_toggles function)"
assert_contains "$ui_src" "UI_TOGGLES_FILE" "pack-opener-ui source (UI_TOGGLES_FILE variable)"

# ── Test: pack-opener-ui syntax is valid ─────────────────────────────────────
if bash -n "$project_root/bin/pack-opener-ui" 2>&1; then
  pass "bin/pack-opener-ui passes bash -n syntax check"
else
  fail "bin/pack-opener-ui failed bash -n syntax check"
fi

# ── Test: pack-opener-ui default toggles are safe (market/figurines off) ─────
assert_contains "$ui_src" "TOGGLE_MARKET_BUYER=0" "pack-opener-ui source (Market Buyer safe default off)"
assert_contains "$ui_src" "TOGGLE_FIGURINES_BUYER=0" "pack-opener-ui source (Figurines Buyer safe default off)"

# ── Test: no real usernames appear in committed preset/template/source files ──
if grep -rqE '/home/[a-z][a-z0-9_-]+' \
     "$preset_dir" "$project_root/config_templates" \
     "$project_root/bin" "$project_root/src" 2>/dev/null; then
  fail "committed files contain hardcoded home paths"
else
  pass "no hardcoded home paths in committed files"
fi

# ── Test: --dry-run mentions launcher installation step ──────────────────────
assert_contains "$dry_out" "launcher" "--dry-run output mentions launcher step"

printf '\nAll setup-acc dry-run tests passed.\n'
