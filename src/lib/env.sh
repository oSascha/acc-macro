#!/usr/bin/env bash

macro_expected_manager_dir() {
  printf '%s\n' "${HOME}/.config/autoclicker/background-static-shop-buyer/gamescope-wayland-attached/"
}

macro_attached_env_file() {
  printf '%s\n' "$(macro_expected_manager_dir)env-attached.txt"
}

macro_manager_dir_exists() {
  test -d "$(macro_expected_manager_dir)"
}

macro_attached_env_exists() {
  test -f "$(macro_attached_env_file)"
}

macro_read_attached_env() {
  local env_file
  env_file="$(macro_attached_env_file)"

  if test -f "$env_file"; then
    awk '{ print }' "$env_file"
  fi
}

macro_attached_env_value() {
  local name="$1"
  local env_file
  env_file="$(macro_attached_env_file)"

  if ! test -f "$env_file"; then
    return 0
  fi

  awk -v key="$name" '
    {
      line = $0
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)
      pattern = "^[[:space:]]*" key "[[:space:]]*="
      if (line ~ pattern) {
        sub(pattern "[[:space:]]*", "", line)
        sub(/[[:space:]]*#.*$/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line ~ /^".*"$/ || line ~ /^\047.*\047$/) {
          line = substr(line, 2, length(line) - 2)
        }
        print line
        exit
      }
    }
  ' "$env_file"
}

macro_attached_display() {
  macro_attached_env_value "DISPLAY"
}

macro_attached_wayland_display() {
  macro_attached_env_value "WAYLAND_DISPLAY"
}
