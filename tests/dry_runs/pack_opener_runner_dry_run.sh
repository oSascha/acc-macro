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

line_number() {
  local pattern="$1"
  local file="$2"

  grep -n -F "$pattern" "$file" | head -n 1 | cut -d: -f1
}

output_file="$(mktemp)"
trap 'rm -f "$output_file"' EXIT

MACRO_INPUT_MODE=dry-run "$project_root/src/modules/pack_opener_runner.sh" --dry-run > "$output_file" 2>&1
output="$(cat "$output_file")"

assert_contains "$output" "TRACE pack-opener-runner start cycles=2" "runner start"
assert_contains "$output" "TRACE pack-opener-runner cycle=1 kind=first begin" "cycle 1 begin"
assert_contains "$output" "TRACE pack-opener-runner cycle=1 phase=place_only runner=place_runner" "cycle 1 place boundary"
assert_contains "$output" "TRACE place-runner start" "place runner start"
assert_contains "$output" "TRACE place-runner complete" "place runner complete"
assert_contains "$output" "TRACE pack-opener-runner cycle=1 phase=return_to_base" "cycle 1 return boundary"
assert_contains "$output" "TRACE pack-opener-runner cycle=1 phase=potion runner=potion_runner" "cycle 1 potion boundary"
assert_contains "$output" "TRACE potion-runner start" "potion runner start"
assert_contains "$output" "TRACE potion-runner complete" "potion runner complete"
assert_contains "$output" "TRACE pack-opener-runner cycle=2 kind=main begin" "cycle 2 begin"
assert_contains "$output" "TRACE pack-opener-runner cycle=2 phase=place_e runner=place_e_runner" "cycle 2 place+E boundary"
assert_contains "$output" "TRACE place-e-runner start" "place+E runner start"
assert_contains "$output" "TRACE place-e-runner complete" "place+E runner complete"
assert_contains "$output" "TRACE pack-opener-runner cycle=2 phase=return_to_base" "cycle 2 return boundary"
assert_contains "$output" "TRACE pack-opener-runner cycle=2 phase=potion runner=potion_runner" "cycle 2 potion boundary"
assert_contains "$output" "TRACE pack-opener-runner complete cycles=2" "runner complete"

live_place_text="live ""place"
live_potion_text="live ""potion"
tool_text="xdo""tool"
repeat_flag="--""repeat"
sync_flag="--""sync"
click_repeat_text="${tool_text} click ${repeat_flag}"
mousemove_sync_text="${tool_text} mousemove ${sync_flag}"
assert_not_contains "$output" "$live_place_text" "runner output"
assert_not_contains "$output" "$live_potion_text" "runner output"
assert_not_contains "$output" "$click_repeat_text" "runner output"
assert_not_contains "$output" "$mousemove_sync_text" "runner output"

cycle1_place_line="$(line_number "TRACE pack-opener-runner cycle=1 phase=place_only runner=place_runner" "$output_file")"
cycle1_return_line="$(line_number "TRACE pack-opener-runner cycle=1 phase=return_to_base" "$output_file")"
cycle2_place_line="$(line_number "TRACE pack-opener-runner cycle=2 phase=place_e runner=place_e_runner" "$output_file")"
cycle2_return_line="$(line_number "TRACE pack-opener-runner cycle=2 phase=return_to_base" "$output_file")"

if awk -v start="$cycle1_place_line" -v stop="$cycle1_return_line" 'NR > start && NR < stop && /TRACE place-e-runner e_tap|xdotool keydown e/ { found = 1 } END { exit found ? 0 : 1 }' "$output_file"; then
  printf 'FAIL: cycle 1 place-only child phase unexpectedly contained E tap traces\n' >&2
  exit 1
fi
printf 'PASS: cycle 1 place-only child phase has no E tap traces\n'

if ! awk -v start="$cycle2_place_line" -v stop="$cycle2_return_line" 'NR > start && NR < stop && /TRACE place-e-runner e_tap|xdotool keydown e/ { found = 1 } END { exit found ? 0 : 1 }' "$output_file"; then
  printf 'FAIL: cycle 2 place+E child phase did not contain E tap traces\n' >&2
  exit 1
fi
printf 'PASS: cycle 2 place+E child phase contains E tap traces\n'

printf 'PASS: pack-opener-runner dry run completed\n'
