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
LOBBY_WALK_SECONDS=2.5
MENU_OPEN_DELAY=0.5
POST_SELECT_CARD_DELAY=0.3
POST_CARD_PICK_DELAY=0.3
POST_DIFFICULTY_SELECT_DELAY=0.3
POST_START_LOAD_DELAY=2.0
ROUND_WAIT_SECONDS=85
RETURN_TO_LOBBY_DELAY=2.0
REPETITIONS_PER_DIFFICULTY=3
EOF

run_dry() {
  MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  STAR_TRIALS_DEFAULTS_FILE="$tmp_dir/defaults.conf" \
    bash -c '. "$1/src/modules/star_trials.sh" && star_trials_dry_run' _ "$project_root" 2>&1
}

run_live_attempt() {
  MACRO_INPUT_MODE=dry-run \
  MACRO_PROJECT_ROOT="$project_root" \
  STAR_TRIALS_DEFAULTS_FILE="$tmp_dir/defaults.conf" \
    bash -c '. "$1/src/modules/star_trials.sh" && star_trials_run' _ "$project_root" 2>&1 || true
}

# Dry-run: prints plan, no live input
output="$(run_dry)"
assert_contains "$output" "DRY-RUN star-trials" "dry-run header"
assert_contains "$output" "imported, disabled, NOT audited for live use" "legacy status"
assert_contains "$output" "lobby_walk_seconds:        2.5" "lobby walk setting"
assert_contains "$output" "round_wait_seconds:        85" "round wait setting"
assert_contains "$output" "repetitions_per_diff:      3" "repetitions setting"
assert_contains "$output" "no live input sent in dry-run" "no live input note"
assert_not_contains "$output" "xdotool" "no xdotool in dry-run"

# star_trials_run() must always refuse with an error (not enabled yet)
live_output="$(run_live_attempt)"
assert_contains "$live_output" "not enabled yet" "live blocked"

printf '\nAll star trials dry-run tests passed.\n'
