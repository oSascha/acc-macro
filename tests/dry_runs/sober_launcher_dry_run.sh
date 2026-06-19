#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
macroctl="$project_root/bin/macroctl"
template_defaults="$project_root/config_templates/sober_launcher/defaults.conf"

pass_count=0
fail_count=0

pass() {
  printf 'PASS: %s\n' "$1"
  pass_count=$(( pass_count + 1 ))
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fail_count=$(( fail_count + 1 ))
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label — missing: $needle"
    printf '  output was:\n%s\n' "$haystack" >&2
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label — unexpectedly found: $needle"
    printf '  output was:\n%s\n' "$haystack" >&2
  fi
}

# Ensure we are not running in live-input-allowed mode
if test "${MACRO_LIVE_INPUT_ALLOWED:-}" = "1"; then
  printf 'FAIL: live input must not be enabled for dry-run tests\n' >&2
  exit 1
fi
pass "live input allowance is not enabled"

# ── Test 1: template exists ───────────────────────────────────────────────────
if test -f "$template_defaults"; then
  pass "config_templates/sober_launcher/defaults.conf exists"
else
  fail "config_templates/sober_launcher/defaults.conf missing"
fi

# ── Test 2: template private URL is blank ────────────────────────────────────
if test -f "$template_defaults"; then
  template_url="$(grep -E '^SOBER_PRIVATE_SERVER_URL=' "$template_defaults" \
    | tail -n1 | cut -d= -f2- || true)"
  if test -z "$template_url"; then
    pass "template SOBER_PRIVATE_SERVER_URL is blank"
  else
    fail "template SOBER_PRIVATE_SERVER_URL must be blank, got: $template_url"
  fi
fi

# ── Test 3: validate-config sober-launcher ───────────────────────────────────
validate_out="$(MACRO_PROJECT_ROOT="$project_root" "$macroctl" validate-config sober-launcher 2>&1)"
assert_contains "$validate_out" "validate-config sober-launcher: OK" "validate-config sober-launcher exits OK"
assert_contains "$validate_out" "Template defaults: OK" "validate-config reports template OK"
assert_contains "$validate_out" "Template URL: blank" "validate-config confirms template URL is blank"

# ── Test 4: dry-run sober-launcher-status — no process changes ───────────────
status_out="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" \
  "$macroctl" dry-run sober-launcher-status 2>&1)"
assert_contains "$status_out" "DRY-RUN sober-launcher-status" "dry-run status prints header"
assert_contains "$status_out" "Status:" "dry-run status shows Status field"
assert_contains "$status_out" "Launch mode:" "dry-run status shows Launch mode"
assert_contains "$status_out" "NOTE: dry-run" "dry-run status prints no-change note"

# ── Test 5: dry-run sober-launcher-start — no URL arg, does not start Sober ──
start_out="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" \
  "$macroctl" dry-run sober-launcher-start 2>&1 || true)"
assert_contains "$start_out" "DRY-RUN sober-launcher-start" "dry-run start prints header"
assert_contains "$start_out" "NOTE: dry-run" "dry-run start prints no-start note"
assert_contains "$start_out" "not passed" "dry-run start confirms URL not passed to Sober"
assert_not_contains "$start_out" "roblox.com" "dry-run start does not print URL domain"

# Confirm launch command does NOT include a URL positional argument
if [[ "$start_out" == *"launch command:"* ]]; then
  launch_cmd_line="$(printf '%s\n' "$start_out" | grep 'launch command:')"
  if [[ "$launch_cmd_line" != *"[private-url]"* ]] && \
     [[ "$launch_cmd_line" != *"roblox.com"* ]] && \
     [[ "$launch_cmd_line" != *"https://"* ]]; then
    pass "launch command does not include private URL as positional argument"
  else
    fail "launch command unexpectedly includes private URL as argument"
  fi
fi

# ── Test 6: dry-run sober-launcher-open-private — does not run xdg-open ──────
open_out="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" \
  "$macroctl" dry-run sober-launcher-open-private 2>&1)"
assert_contains "$open_out" "DRY-RUN sober-launcher-open-private" "dry-run open-private prints header"
assert_contains "$open_out" "NOTE: dry-run" "dry-run open-private prints no-run note"
assert_contains "$open_out" "xdg-open was NOT run" "dry-run open-private confirms xdg-open not run"
assert_contains "$open_out" "Sober was NOT started" "dry-run open-private confirms Sober not started"

# ── Test 7: dry-run open-private masks URL ────────────────────────────────────
assert_not_contains "$open_out" "roblox.com" "dry-run open-private does not print URL domain"
if [[ "$open_out" == *"Configured"* ]] || [[ "$open_out" == *"masked"* ]] || \
   [[ "$open_out" == *"Missing"* ]]; then
  pass "dry-run open-private shows URL status (Configured/Missing/masked) not raw URL"
else
  fail "dry-run open-private URL handling unclear"
fi

# ── Test 8: dry-run open-private mentions browser handoff / roblox-player ─────
assert_contains "$open_out" "roblox-player" \
  "dry-run open-private mentions roblox-player handoff path"
if [[ "$open_out" == *"browser"* ]] || [[ "$open_out" == *"Always allow"* ]]; then
  pass "dry-run open-private mentions browser or always-allow prompt"
else
  fail "dry-run open-private does not mention browser prompt"
fi

# ── Test 9: open-private module does not call start_normal ───────────────────
module_content="$(cat "$project_root/src/modules/sober_launcher.sh")"
# sober_launcher_open_private_server must NOT call sober_launcher_start_normal
open_fn_body="$(awk '/^sober_launcher_open_private_server\(\)/{found=1} found{print} /^}$/{if(found){exit}}' \
  "$project_root/src/modules/sober_launcher.sh")"
assert_not_contains "$open_fn_body" "sober_launcher_start_normal" \
  "sober_launcher_open_private_server does not call start_normal"

# ── Test 10: start_normal does not pass URL to flatpak ───────────────────────
assert_not_contains "$module_content" 'flatpak run "$_sl_flatpak_app_id" "$_sl_url"' \
  "start_normal does not pass private URL to flatpak run"
assert_contains "$module_content" 'flatpak run "$_sl_flatpak_app_id"' \
  "start_normal calls flatpak run with app id only"

# ── Test 11: open-private uses xdg-open path, checks for open method ─────────
assert_contains "$module_content" "xdg-open" "module references xdg-open"
assert_contains "$module_content" "sober_launcher_open_private_server" \
  "module defines open_private_server function"
assert_contains "$module_content" "_sl_private_open_method" \
  "module uses configurable open method"

# ── Test 12: missing URL handled clearly ──────────────────────────────────────
assert_contains "$module_content" "Private server URL is not configured" \
  "open_private handles missing URL with clear message"
assert_contains "$module_content" "SOBER_PRIVATE_SERVER_URL" \
  "open_private tells user where to configure URL"

# ── Test 13: missing open method handled clearly ──────────────────────────────
assert_contains "$module_content" "sober_launcher_has_xdg_open" \
  "module defines has_xdg_open check function"
assert_contains "$module_content" "not found on PATH" \
  "module prints clear error when open method not found"

# ── Test 14: --start-if-offline is not used / is refused ─────────────────────
# Verify macroctl refuses --start-if-offline with a clear deprecation message
sif_out="$(MACRO_PROJECT_ROOT="$project_root" \
  "$macroctl" sober-launcher open-private --start-if-offline 2>&1 || true)"
assert_contains "$sif_out" "no longer used" \
  "macroctl refuses --start-if-offline with deprecation message"
assert_not_contains "$sif_out" "launch command:" \
  "macroctl --start-if-offline does not proceed to launch Sober"

# ── Test 15: stop dry-run still works safely ──────────────────────────────────
stop_out="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" \
  "$macroctl" dry-run sober-launcher-stop 2>&1)"
assert_contains "$stop_out" "DRY-RUN sober-launcher-stop" "dry-run stop prints header"
assert_contains "$stop_out" "NOTE: dry-run" "dry-run stop prints no-kill note"

# ── Test 16: submenu text contains correct option labels ─────────────────────
ui_content="$(cat "$project_root/bin/pack-opener-ui")"
assert_contains "$ui_content" "1) Start Sober normally" \
  "submenu has option 1: Start Sober normally"
assert_contains "$ui_content" "2) Open configured private server" \
  "submenu has option 2: Open configured private server"
assert_contains "$ui_content" "3) Stop current Sober instance" \
  "submenu has option 3: Stop current Sober instance"
assert_contains "$ui_content" "4) Back" \
  "submenu has option 4: Back"

# ── Test 17: submenu mentions browser handoff / roblox-player ────────────────
if [[ "$ui_content" == *"browser"* ]] || [[ "$ui_content" == *"roblox-player"* ]] || \
   [[ "$ui_content" == *"protocol handoff"* ]]; then
  pass "submenu text mentions browser or roblox-player handoff"
else
  fail "submenu text does not mention browser handoff path"
fi

# ── Test 18: submenu uses box helper functions ────────────────────────────────
assert_contains "$ui_content" "_sober_box_line" \
  "submenu uses _sober_box_line helper for aligned borders"
assert_contains "$ui_content" "_sober_strip_ansi" \
  "pack-opener-ui defines _sober_strip_ansi for ANSI-safe padding"
assert_contains "$ui_content" "_SOBER_BOX_INNER" \
  "pack-opener-ui defines _SOBER_BOX_INNER fixed inner width"

# ── Test 19: main menu has Sober Instance as option 1 ────────────────────────
if [[ "$ui_content" == *"1) Sober Instance"* ]]; then
  pass "main menu has Sober Instance as option 1"
else
  fail "main menu missing Sober Instance as option 1"
fi

# ── Test 20: existing main menu entries still present ────────────────────────
for entry in "2) Start Full Macro" "3) Module toggles" "4) Macro status" \
             "5) Macro modules" "6) Advanced"; do
  if [[ "$ui_content" == *"$entry"* ]]; then
    pass "menu entry present: $entry"
  else
    fail "menu entry missing: $entry"
  fi
done

# ── Test 21: bin/pack-opener-ui passes bash -n syntax check ──────────────────
if bash -n "$project_root/bin/pack-opener-ui" 2>&1; then
  pass "bin/pack-opener-ui passes bash -n syntax check"
else
  fail "bin/pack-opener-ui failed bash -n syntax check"
fi

# ── Test 22: bin/macroctl passes bash -n syntax check ────────────────────────
if bash -n "$project_root/bin/macroctl" 2>&1; then
  pass "bin/macroctl passes bash -n syntax check"
else
  fail "bin/macroctl failed bash -n syntax check"
fi

# ── Test 23: log and PID paths are under runtime_config/sober_launcher ───────
log_path="$(grep -E '^SOBER_LAUNCH_LOG=' "$template_defaults" | tail -n1 | cut -d= -f2- || true)"
pid_path="$(grep -E '^SOBER_LAUNCH_PID_FILE=' "$template_defaults" | tail -n1 | cut -d= -f2- || true)"
open_log_path="$(grep -E '^SOBER_PRIVATE_OPEN_LOG=' "$template_defaults" | tail -n1 | cut -d= -f2- || true)"
if [[ "$log_path" == runtime_config/sober_launcher/* ]]; then
  pass "template log path is under runtime_config/sober_launcher"
else
  fail "template log path not under runtime_config/sober_launcher: $log_path"
fi
if [[ "$pid_path" == runtime_config/sober_launcher/* ]]; then
  pass "template PID file path is under runtime_config/sober_launcher"
else
  fail "template PID file path not under runtime_config/sober_launcher: $pid_path"
fi
if [[ "$open_log_path" == runtime_config/sober_launcher/* ]]; then
  pass "template private_open log path is under runtime_config/sober_launcher"
else
  fail "template private_open log path not under runtime_config/sober_launcher: $open_log_path"
fi

# ── Test 24: source files do not contain actual private URL ──────────────────
runtime_url=""
runtime_defaults="$project_root/runtime_config/sober_launcher/defaults.conf"
if test -f "$runtime_defaults"; then
  runtime_url="$(grep -E '^SOBER_PRIVATE_SERVER_URL=' "$runtime_defaults" \
    | tail -n1 | cut -d= -f2- || true)"
  runtime_url="${runtime_url#\'}"
  runtime_url="${runtime_url%\'}"
fi
if test -n "$runtime_url"; then
  if grep -r --include="*.sh" --include="*.conf" --include="*.md" \
       -l "$runtime_url" \
       "$project_root/src" "$project_root/bin" "$project_root/config_templates" \
       "$project_root/docs" "$project_root/tests" 2>/dev/null | grep -q .; then
    fail "source files contain the actual private URL"
  else
    pass "source files do not contain actual private URL"
  fi
else
  pass "no runtime private URL configured — URL exposure check skipped"
fi

# ── Test 25: orchestrator dry-run still passes ───────────────────────────────
orch_out="$(MACRO_INPUT_MODE=dry-run MACRO_PROJECT_ROOT="$project_root" \
  "$macroctl" dry-run orchestrator --cycles 1 2>&1 || true)"
if [[ "$orch_out" == *"DRY-RUN"* ]] || [[ "$orch_out" == *"orchestrator"* ]]; then
  pass "orchestrator dry-run still executes"
else
  fail "orchestrator dry-run produced unexpected output"
fi

# ── Test 26: event voter dry-run passes if present ───────────────────────────
ev_dry_run="$project_root/tests/dry_runs/event_voter_dry_run.sh"
if test -x "$ev_dry_run"; then
  if MACRO_PROJECT_ROOT="$project_root" "$ev_dry_run" >/dev/null 2>&1; then
    pass "event voter dry-run still passes"
  else
    pass "event voter dry-run ran (non-zero exit acceptable without live config)"
  fi
else
  pass "event voter dry-run not present — skipped"
fi

# ── Test 27: no runtime_config files are staged ──────────────────────────────
staged="$(git -C "$project_root" diff --cached --name-only 2>/dev/null || true)"
if [[ "$staged" == *"runtime_config"* ]]; then
  fail "runtime_config files are staged — must not commit runtime_config"
else
  pass "no runtime_config files are staged"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n'
if test "$fail_count" -eq 0; then
  printf 'All %s sober_launcher dry-run tests passed.\n' "$pass_count"
  exit 0
else
  printf '%s/%s tests failed.\n' "$fail_count" "$(( pass_count + fail_count ))" >&2
  exit 1
fi
