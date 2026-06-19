#!/usr/bin/env bash
# Sober Instance Launcher — manages launching/stopping Sober inside Gamescope
# and opening a configured private server link via xdg-open separately.
# Private server URL lives only in runtime_config/sober_launcher/defaults.conf.
# All live actions are NO-OPs in dry-run/test mode.
#
# Note: Passing the private server URL as a positional argument to
# `flatpak run org.vinegarhq.Sober` did not reliably join the private server
# in live testing. The launcher therefore separates normal Sober startup from
# private server opening.

_sober_launcher_script="${BASH_SOURCE[0]}"
_sober_launcher_dir="${_sober_launcher_script%/*}"
if test "$_sober_launcher_dir" = "$_sober_launcher_script"; then
  _sober_launcher_dir="."
fi

_sober_launcher_project_root="${MACRO_PROJECT_ROOT:-}"
if test -z "$_sober_launcher_project_root"; then
  _sober_launcher_project_root="$(cd "$_sober_launcher_dir/../.." && pwd -P)"
fi

# shellcheck source=../lib/config.sh
. "$_sober_launcher_project_root/src/lib/config.sh"

# Loaded settings (defaults)
_sl_enabled="1"
_sl_url=""
_sl_width="800"
_sl_height="600"
_sl_refresh="60"
_sl_gamescope_args=""
_sl_flatpak_app_id="org.vinegarhq.Sober"
_sl_log_path=""
_sl_pid_file=""
_sl_private_open_method="xdg-open"
_sl_private_open_wait_seconds="10"
_sl_private_open_log=""

_sl_runtime_dir=""
_sl_pid_file_abs=""
_sl_log_path_abs=""
_sl_private_open_log_abs=""

sober_launcher_load_config() {
  local runtime_dir template_dir defaults_file

  runtime_dir="$(config_sober_launcher_dir)"
  template_dir="$(config_sober_launcher_template_dir)"
  defaults_file="$(config_sober_launcher_defaults_file)"

  _sl_runtime_dir="$runtime_dir"

  # Bootstrap runtime dir from template (never overwrites existing)
  mkdir -p "$runtime_dir"
  if ! test -f "$defaults_file" && test -f "$template_dir/defaults.conf"; then
    cp "$template_dir/defaults.conf" "$defaults_file"
  fi

  if test -f "$defaults_file"; then
    # shellcheck source=/dev/null
    . "$defaults_file"
  fi

  _sl_enabled="${SOBER_LAUNCHER_ENABLED:-1}"
  _sl_url="${SOBER_PRIVATE_SERVER_URL:-}"
  _sl_width="${SOBER_LAUNCH_WIDTH:-800}"
  _sl_height="${SOBER_LAUNCH_HEIGHT:-600}"
  _sl_refresh="${SOBER_LAUNCH_REFRESH:-60}"
  _sl_gamescope_args="${SOBER_LAUNCH_GAMESCOPE_ARGS:-}"
  _sl_flatpak_app_id="${SOBER_FLATPAK_APP_ID:-org.vinegarhq.Sober}"
  _sl_log_path="${SOBER_LAUNCH_LOG:-runtime_config/sober_launcher/launcher.log}"
  _sl_pid_file="${SOBER_LAUNCH_PID_FILE:-runtime_config/sober_launcher/pids.env}"
  _sl_private_open_method="${SOBER_PRIVATE_OPEN_METHOD:-xdg-open}"
  _sl_private_open_wait_seconds="${SOBER_PRIVATE_OPEN_WAIT_SECONDS:-10}"
  _sl_private_open_log="${SOBER_PRIVATE_OPEN_LOG:-runtime_config/sober_launcher/private_open.log}"

  # Make all runtime paths absolute relative to project root
  local root
  root="$(config_project_root)"
  case "$_sl_log_path" in
    /*) _sl_log_path_abs="$_sl_log_path" ;;
    *)  _sl_log_path_abs="$root/$_sl_log_path" ;;
  esac
  case "$_sl_pid_file" in
    /*) _sl_pid_file_abs="$_sl_pid_file" ;;
    *)  _sl_pid_file_abs="$root/$_sl_pid_file" ;;
  esac
  case "$_sl_private_open_log" in
    /*) _sl_private_open_log_abs="$_sl_private_open_log" ;;
    *)  _sl_private_open_log_abs="$root/$_sl_private_open_log" ;;
  esac

  # Fallback: read private URL from recovery config if not set here
  if test -z "$_sl_url"; then
    local rec_defaults
    rec_defaults="$(config_recovery_dir)/defaults.conf"
    if test -f "$rec_defaults"; then
      local rec_url
      rec_url="$(grep -E '^RECOVERY_PRIVATE_SERVER_URL=' "$rec_defaults" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
      # Strip surrounding single quotes if present
      rec_url="${rec_url#\'}"
      rec_url="${rec_url%\'}"
      if test -n "$rec_url"; then
        _sl_url="$rec_url"
      fi
    fi
  fi
}

sober_launcher_has_private_url() {
  test -n "$_sl_url"
}

sober_launcher_has_xdg_open() {
  command -v "$_sl_private_open_method" >/dev/null 2>&1
}

# Returns a masked representation of the URL for safe output.
sober_launcher_mask_url() {
  if test -n "$_sl_url"; then
    printf '[configured — masked]'
  else
    printf '[not configured]'
  fi
}

# Returns "live", "live_untracked", or "offline"
sober_launcher_status() {
  # Prefer PID file tracking
  if test -f "$_sl_pid_file_abs"; then
    local pid
    pid="$(grep -E '^SOBER_PID=' "$_sl_pid_file_abs" 2>/dev/null | tail -n1 | cut -d= -f2 || true)"
    if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
      printf 'live'
      return 0
    fi
  fi

  # Fallback: pgrep detection
  if sober_launcher_find_existing_processes >/dev/null 2>&1; then
    printf 'live_untracked'
    return 0
  fi

  printf 'offline'
}

# Prints PIDs of any gamescope/sober processes (for detection only).
sober_launcher_find_existing_processes() {
  local found=0
  local pids

  pids="$(pgrep -x gamescope 2>/dev/null || true)"
  if test -n "$pids"; then
    printf '%s\n' "$pids"
    found=1
  fi

  pids="$(pgrep -f "$_sl_flatpak_app_id" 2>/dev/null || true)"
  if test -n "$pids"; then
    printf '%s\n' "$pids"
    found=1
  fi

  pids="$(pgrep -ix sober 2>/dev/null || true)"
  if test -n "$pids"; then
    printf '%s\n' "$pids"
    found=1
  fi

  return $(( 1 - found ))
}

sober_launcher_runtime_setup() {
  mkdir -p "$_sl_runtime_dir"
}

sober_launcher_print_status() {
  local status url_status
  status="$(sober_launcher_status)"
  if sober_launcher_has_private_url; then
    url_status="Configured"
  else
    url_status="Missing"
  fi

  printf 'Sober Instance\n'
  printf 'Status:              '
  case "$status" in
    live)           printf 'Live\n' ;;
    live_untracked) printf 'Live (untracked)\n' ;;
    offline)        printf 'Offline\n' ;;
    *)              printf '%s\n' "$status" ;;
  esac
  printf 'Private server link: %s\n' "$url_status"
  printf 'Launch mode:         Browser handoff + Sober in Gamescope\n'
  printf 'Gamescope size:      %sx%s @ %s Hz\n' "$_sl_width" "$_sl_height" "$_sl_refresh"
}

# Start Sober inside Gamescope normally (no URL argument passed to Sober).
# In dry-run/test mode: prints plan, does nothing.
sober_launcher_start_normal() {
  local dry_run="${1:-}"

  local gamescope_cmd
  gamescope_cmd="gamescope -W ${_sl_width} -H ${_sl_height} -r ${_sl_refresh}"
  if test -n "$_sl_gamescope_args"; then
    gamescope_cmd="$gamescope_cmd ${_sl_gamescope_args}"
  fi
  gamescope_cmd="$gamescope_cmd -- flatpak run ${_sl_flatpak_app_id}"

  if test "${dry_run:-}" = "--dry-run" || test "${MACRO_INPUT_MODE:-}" = "dry-run"; then
    printf 'DRY-RUN sober-launcher-start\n'
    printf '  flatpak app:     %s\n' "$_sl_flatpak_app_id"
    printf '  gamescope size:  %sx%s @ %s Hz\n' "$_sl_width" "$_sl_height" "$_sl_refresh"
    printf '  gamescope args:  %s\n' "${_sl_gamescope_args:-(none)}"
    printf '  private URL:     not passed (start normal only)\n'
    printf '  log:             %s\n' "$_sl_log_path_abs"
    printf '  pid file:        %s\n' "$_sl_pid_file_abs"
    printf '  launch command:  %s\n' "$gamescope_cmd"
    printf '  NOTE: dry-run — Sober was NOT started\n'
    return 0
  fi

  sober_launcher_runtime_setup

  printf 'Starting Sober inside Gamescope...\n'

  # Launch detached so the terminal/UI stays usable.
  # The private server URL is NOT passed here — use open-private separately.
  gamescope \
    -W "$_sl_width" -H "$_sl_height" -r "$_sl_refresh" \
    ${_sl_gamescope_args:+$_sl_gamescope_args} \
    -- flatpak run "$_sl_flatpak_app_id" \
    >> "$_sl_log_path_abs" 2>&1 &
  local launched_pid=$!

  printf 'SOBER_PID=%s\n' "$launched_pid" > "$_sl_pid_file_abs"
  printf 'Sober launched (PID %s). Log: %s\n' "$launched_pid" "$_sl_log_path_abs"
  return 0
}

# sober_launcher_start is an alias for sober_launcher_start_normal.
sober_launcher_start() {
  sober_launcher_start_normal "$@"
}

# Log the result of a private-server open action (URL is never written to log).
sober_launcher_log_private_open_result() {
  local result="$1"
  local timestamp
  timestamp="$(date +%Y-%m-%dT%H:%M:%S%z)"
  printf '%s open-private: %s\n' "$timestamp" "$result" >> "$_sl_private_open_log_abs" 2>/dev/null || true
}

# Dry-run: prints what open-private would do, does nothing real.
sober_launcher_open_private_server_dry_run() {
  local url_status open_method_status
  if sober_launcher_has_private_url; then
    url_status="Configured"
  else
    url_status="Missing"
  fi
  if sober_launcher_has_xdg_open; then
    open_method_status="${_sl_private_open_method} (found)"
  else
    open_method_status="${_sl_private_open_method} (NOT FOUND on PATH)"
  fi

  local sl_status
  sl_status="$(sober_launcher_status)"

  printf 'DRY-RUN sober-launcher-open-private\n'
  printf '  private URL:    %s\n' "$url_status"
  printf '  URL value:      %s\n' "$(sober_launcher_mask_url)"
  printf '  open method:    %s\n' "$open_method_status"
  printf '  sober status:   %s\n' "$sl_status"
  printf '  open log:       %s\n' "$_sl_private_open_log_abs"
  printf '  action plan:    %s [masked private-server web URL]\n' "$_sl_private_open_method"
  printf '  handoff path:   browser -> roblox-player URI -> sober-gamescope-url -> Sober in Gamescope\n'
  printf '  NOTE: dry-run — xdg-open was NOT run, Sober was NOT started/stopped\n'
  printf '  NOTE: browser may ask to open roblox-player link; "Always allow" removes future prompts\n'
}

# Open the configured private server web URL via xdg-open.
# The browser handles the roblox-player URI protocol handoff to Sober.
# Sober is NOT started here — the protocol handoff launches it.
# In dry-run/test mode: delegates to dry_run variant, does nothing real.
sober_launcher_open_private_server() {
  if test "${MACRO_INPUT_MODE:-}" = "dry-run"; then
    sober_launcher_open_private_server_dry_run
    return 0
  fi

  # Check URL configured
  if ! sober_launcher_has_private_url; then
    printf 'ERROR: Private server URL is not configured.\n' >&2
    printf '  Set SOBER_PRIVATE_SERVER_URL in runtime_config/sober_launcher/defaults.conf\n' >&2
    printf '  See docs/SOBER_INSTANCE_LAUNCHER.md for setup instructions.\n' >&2
    return 1
  fi

  # Check open method available
  if ! sober_launcher_has_xdg_open; then
    printf 'ERROR: %s not found on PATH.\n' "$_sl_private_open_method" >&2
    printf '  Install xdg-utils or set SOBER_PRIVATE_OPEN_METHOD to an available command.\n' >&2
    return 1
  fi

  sober_launcher_runtime_setup

  # Open private server web URL — the browser/roblox-player handoff launches Sober.
  # URL is not printed.
  printf 'Opening configured private server link...\n'
  printf '(Your browser may ask to open the roblox-player link — select "Always allow..." to avoid future prompts.)\n'
  "$_sl_private_open_method" "$_sl_url" >> "$_sl_private_open_log_abs" 2>&1 &
  local open_pid=$!
  sober_launcher_log_private_open_result "launched (PID $open_pid)"
  printf 'Private server link opened. Log: %s\n' "$_sl_private_open_log_abs"
  return 0
}

# Stop the tracked Sober/Gamescope instance.
# In dry-run/test mode: prints plan, does nothing.
sober_launcher_stop() {
  local dry_run="${1:-}"

  if test "${dry_run:-}" = "--dry-run" || test "${MACRO_INPUT_MODE:-}" = "dry-run"; then
    local pid_info="(no PID file)"
    if test -f "$_sl_pid_file_abs"; then
      local pid
      pid="$(grep -E '^SOBER_PID=' "$_sl_pid_file_abs" 2>/dev/null | tail -n1 | cut -d= -f2 || true)"
      if test -n "$pid"; then
        pid_info="PID $pid from PID file"
      fi
    fi
    printf 'DRY-RUN sober-launcher-stop\n'
    printf '  would stop: %s\n' "$pid_info"
    printf '  pid file:   %s\n' "$_sl_pid_file_abs"
    printf '  NOTE: dry-run — nothing was killed\n'
    return 0
  fi

  local status
  status="$(sober_launcher_status)"

  if test "$status" = "offline"; then
    printf 'No Sober instance appears to be running.\n'
    return 0
  fi

  # Try PID file first
  if test -f "$_sl_pid_file_abs"; then
    local pid
    pid="$(grep -E '^SOBER_PID=' "$_sl_pid_file_abs" 2>/dev/null | tail -n1 | cut -d= -f2 || true)"
    if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
      printf 'Stopping Sober (PID %s)...\n' "$pid"
      kill "$pid" 2>/dev/null || true
      local waited=0
      while kill -0 "$pid" 2>/dev/null && test "$waited" -lt 5; do
        sleep 1
        waited=$(( waited + 1 ))
      done
      if kill -0 "$pid" 2>/dev/null; then
        printf 'Process still running — force killing...\n'
        kill -9 "$pid" 2>/dev/null || true
      fi
      rm -f "$_sl_pid_file_abs"
      printf 'Stopped.\n'
      return 0
    fi
    rm -f "$_sl_pid_file_abs"
  fi

  # Untracked: caller must confirm before reaching here
  printf 'Stopping untracked Sober/Gamescope processes...\n'
  pkill -x gamescope 2>/dev/null || true
  pkill -f "$_sl_flatpak_app_id" 2>/dev/null || true
  pkill -ix sober 2>/dev/null || true
  printf 'Stop signals sent.\n'
  return 0
}
