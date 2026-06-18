#!/usr/bin/env bash

parse_duration_ms() {
  local value="${1:-}"
  local rest
  local total=0
  local number
  local unit

  if test -z "$value"; then
    printf 'ERROR: duration is required\n' >&2
    return 2
  fi

  rest="$value"
  while test -n "$rest"; do
    if [[ "$rest" =~ ^([0-9]+)(ms|s)(.*)$ ]]; then
      number="${BASH_REMATCH[1]}"
      unit="${BASH_REMATCH[2]}"
      rest="${BASH_REMATCH[3]}"

      case "$unit" in
        ms)
          total=$((total + number))
          ;;
        s)
          total=$((total + (number * 1000)))
          ;;
        *)
          printf 'ERROR: invalid duration unit in %s\n' "$value" >&2
          return 2
          ;;
      esac
    else
      printf 'ERROR: invalid duration: %s\n' "$value" >&2
      return 2
    fi
  done

  printf '%s\n' "$total"
}

sleep_duration() {
  local value="${1:-}"
  local ms
  local seconds
  local remainder
  local sleep_value

  if ! ms="$(parse_duration_ms "$value")"; then
    return 2
  fi

  seconds=$((ms / 1000))
  remainder=$((ms % 1000))

  if test "$remainder" -eq 0; then
    sleep "$seconds"
  else
    printf -v sleep_value '%s.%03d' "$seconds" "$remainder"
    sleep "$sleep_value"
  fi
}
