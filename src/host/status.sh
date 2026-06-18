#!/usr/bin/env bash
set -euo pipefail

project_root="${MACRO_PROJECT_ROOT:-$(pwd)}"

# shellcheck source=../lib/env.sh
. "$project_root/src/lib/env.sh"
# shellcheck source=../lib/logging.sh
. "$project_root/src/lib/logging.sh"

manager_dir="$(macro_expected_manager_dir)"
env_file="$(macro_attached_env_file)"
attached_display="$(macro_attached_display)"
attached_wayland_display="$(macro_attached_wayland_display)"

exists_text() {
  if test "$1" = "yes"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

path_exists_text() {
  if test -e "$1"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

dir_exists_text() {
  if test -d "$1"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

process_running_text() {
  local pattern="$1"

  if pgrep -af "$pattern" >/dev/null 2>&1; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

value_or_missing() {
  if test -n "$1"; then
    printf '%s\n' "$1"
  else
    printf '(not found)\n'
  fi
}

printf 'Host/session status\n'
printf '\n'
printf 'Project root: %s\n' "$project_root"
printf 'Expected manager directory: %s\n' "$manager_dir"
printf 'Manager directory exists: %s\n' "$(dir_exists_text "$manager_dir")"
printf 'env-attached.txt exists: %s\n' "$(path_exists_text "$env_file")"
printf 'Parsed DISPLAY: %s\n' "$(value_or_missing "$attached_display")"
printf 'Parsed WAYLAND_DISPLAY: %s\n' "$(value_or_missing "$attached_wayland_display")"
printf 'Gamescope process appears running: %s\n' "$(process_running_text 'gamescope|gamescopereaper|run-wayland-sober-manager[.]sh')"
printf 'Sober process appears running: %s\n' "$(process_running_text 'org[.]vinegarhq[.]Sober|bwrap.*sober|sober_exe|Sober')"
printf '\n'
printf 'Manager log files\n'
printf 'gamescope-manager.log: %s\n' "$(path_exists_text "${manager_dir}gamescope-manager.log")"
printf 'gamescope-manager-wrapper.log: %s\n' "$(path_exists_text "${manager_dir}gamescope-manager-wrapper.log")"
printf 'sober-manager-sober.log: %s\n' "$(path_exists_text "${manager_dir}sober-manager-sober.log")"
