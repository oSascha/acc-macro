#!/usr/bin/env bash

points_lib_dir="${BASH_SOURCE[0]%/*}"
if test "$points_lib_dir" = "${BASH_SOURCE[0]}"; then
  points_lib_dir="."
fi

# shellcheck source=timing.sh
. "$points_lib_dir/timing.sh"

declare -A __points_x=()
declare -A __points_y=()
declare -A __points_x_seen=()
declare -A __points_y_seen=()
declare -A __points_seen=()
declare -a __points_names=()

declare -A __timing_values=()
declare -A __timing_seen=()
declare -a __timing_names=()

__trim() {
  local value="$1"

  while [[ "$value" =~ ^[[:space:]] ]]; do
    value="${value:1}"
  done

  while [[ "$value" =~ [[:space:]]$ ]]; do
    value="${value:0:${#value}-1}"
  done

  printf '%s\n' "$value"
}

__unquote() {
  local value="$1"

  if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s\n' "$value"
}

__record_point_name() {
  local name="$1"

  if test -z "${__points_seen[$name]+x}"; then
    __points_seen["$name"]=1
    __points_names+=("$name")
  fi
}

__points_store_axis() {
  local name="$1"
  local axis="$2"
  local value="$3"

  __record_point_name "$name"
  case "$axis" in
    x)
      __points_x["$name"]="$value"
      __points_x_seen["$name"]=1
      ;;
    y)
      __points_y["$name"]="$value"
      __points_y_seen["$name"]=1
      ;;
  esac
}

__points_store_pair() {
  local name="$1"
  local x="$2"
  local y="$3"

  __record_point_name "$name"
  __points_x["$name"]="$x"
  __points_y["$name"]="$y"
  __points_x_seen["$name"]=1
  __points_y_seen["$name"]=1
}

__parse_point_pair_text() {
  local text="$1"
  local x=""
  local y=""

  if [[ "$text" =~ (^|[[:space:]])x[[:space:]]*=[[:space:]]*([^[:space:]]+) ]]; then
    x="${BASH_REMATCH[2]}"
  fi

  if [[ "$text" =~ (^|[[:space:]])y[[:space:]]*=[[:space:]]*([^[:space:]]+) ]]; then
    y="${BASH_REMATCH[2]}"
  fi

  if test -n "$x" && test -n "$y"; then
    printf '%s\t%s\n' "$x" "$y"
    return 0
  fi

  return 1
}

points_load() {
  local file="${1:-}"
  local raw
  local line
  local key
  local value
  local name
  local parsed
  local x
  local y

  if test -z "$file" || ! test -f "$file"; then
    printf 'ERROR: points file not found: %s\n' "$file" >&2
    return 2
  fi

  __points_x=()
  __points_y=()
  __points_x_seen=()
  __points_y_seen=()
  __points_seen=()
  __points_names=()

  while IFS= read -r raw || test -n "$raw"; do
    line="${raw%%#*}"
    line="$(__trim "$line")"

    if test -z "$line"; then
      continue
    fi

    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="$(__trim "${BASH_REMATCH[2]}")"
      value="$(__unquote "$value")"

      case "$key" in
        *_X)
          name="${key%_X}"
          __points_store_axis "$name" x "$value"
          ;;
        *_Y)
          name="${key%_Y}"
          __points_store_axis "$name" y "$value"
          ;;
        *)
          if parsed="$(__parse_point_pair_text "$value")"; then
            x="${parsed%%	*}"
            y="${parsed#*	}"
            __points_store_pair "$key" "$x" "$y"
          fi
          ;;
      esac
      continue
    fi

    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+(.+)$ ]]; then
      name="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      if parsed="$(__parse_point_pair_text "$value")"; then
        x="${parsed%%	*}"
        y="${parsed#*	}"
        __points_store_pair "$name" "$x" "$y"
      fi
    fi
  done < "$file"
}

__coordinate_is_unset() {
  local value="${1-}"

  test -z "$value" || test "$value" = "unset"
}

__coordinate_is_valid() {
  local value="${1-}"

  [[ "$value" =~ ^[0-9]+$ ]]
}

__point_status() {
  local name="$1"
  local x="${__points_x[$name]-}"
  local y="${__points_y[$name]-}"

  if test -z "${__points_seen[$name]+x}"; then
    printf 'missing\n'
  elif test -z "${__points_x_seen[$name]+x}" || test -z "${__points_y_seen[$name]+x}"; then
    printf 'missing\n'
  elif __coordinate_is_unset "$x" || __coordinate_is_unset "$y"; then
    printf 'unset\n'
  elif __coordinate_is_valid "$x" && __coordinate_is_valid "$y"; then
    printf 'valid\n'
  else
    printf 'invalid\n'
  fi
}

points_get() {
  local name="${1:-}"
  local status

  if test -z "$name"; then
    printf 'ERROR: points_get requires a name\n' >&2
    return 2
  fi

  status="$(__point_status "$name")"
  case "$status" in
    valid)
      printf '%s,%s\n' "${__points_x[$name]}" "${__points_y[$name]}"
      ;;
    missing)
      printf 'ERROR: point missing: %s\n' "$name" >&2
      return 1
      ;;
    unset)
      printf 'ERROR: point unset: %s\n' "$name" >&2
      return 1
      ;;
    invalid)
      printf 'ERROR: point invalid: %s x=%s y=%s\n' "$name" "${__points_x[$name]-}" "${__points_y[$name]-}" >&2
      return 1
      ;;
  esac
}

points_is_set() {
  local name="${1:-}"

  test "$(__point_status "$name")" = "valid"
}

points_print_all() {
  local name
  local status

  for name in "${__points_names[@]}"; do
    status="$(__point_status "$name")"
    printf 'POINT %s x=%s y=%s status=%s\n' "$name" "${__points_x[$name]-}" "${__points_y[$name]-}" "$status"
  done
}

points_validate_required() {
  local required_file="${1:-}"
  local raw
  local name
  local status
  local failures=0

  if test -z "$required_file" || ! test -f "$required_file"; then
    printf 'ERROR: required points file not found: %s\n' "$required_file" >&2
    return 2
  fi

  while IFS= read -r raw || test -n "$raw"; do
    name="${raw%%#*}"
    name="$(__trim "$name")"

    if test -z "$name"; then
      continue
    fi

    status="$(__point_status "$name")"
    case "$status" in
      valid)
        printf 'OK: point %s = %s,%s\n' "$name" "${__points_x[$name]}" "${__points_y[$name]}"
        ;;
      missing)
        printf 'MISSING: point %s\n' "$name"
        failures=$((failures + 1))
        ;;
      unset)
        printf 'UNSET: point %s x=%s y=%s\n' "$name" "${__points_x[$name]-}" "${__points_y[$name]-}"
        failures=$((failures + 1))
        ;;
      invalid)
        printf 'INVALID: point %s x=%s y=%s\n' "$name" "${__points_x[$name]-}" "${__points_y[$name]-}"
        failures=$((failures + 1))
        ;;
    esac
  done < "$required_file"

  test "$failures" -eq 0
}

__record_timing_name() {
  local name="$1"

  if test -z "${__timing_seen[$name]+x}"; then
    __timing_seen["$name"]=1
    __timing_names+=("$name")
  fi
}

timing_load() {
  local file="${1:-}"
  local raw
  local line
  local key
  local value

  if test -z "$file" || ! test -f "$file"; then
    printf 'ERROR: timing file not found: %s\n' "$file" >&2
    return 2
  fi

  __timing_values=()
  __timing_seen=()
  __timing_names=()

  while IFS= read -r raw || test -n "$raw"; do
    line="${raw%%#*}"
    line="$(__trim "$line")"

    if test -z "$line"; then
      continue
    fi

    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="$(__trim "${BASH_REMATCH[2]}")"
      value="$(__unquote "$value")"
      __record_timing_name "$key"
      __timing_values["$key"]="$value"
    fi
  done < "$file"
}

timing_get() {
  local name="${1:-}"

  if test -z "$name"; then
    printf 'ERROR: timing_get requires a name\n' >&2
    return 2
  fi

  if test -z "${__timing_seen[$name]+x}"; then
    printf 'ERROR: timing missing: %s\n' "$name" >&2
    return 1
  fi

  printf '%s\n' "${__timing_values[$name]}"
}

__timing_value_kind() {
  local name="$1"

  case "$name" in
    *_DURATION|*_WAIT|*_DELAY|*_INTERVAL|*_GAP)
      printf 'duration\n'
      ;;
    *_COUNT|*_SIZE)
      printf 'integer\n'
      ;;
    *_ENABLED|CLOSE_INVENTORY|PACK_FINAL_MOUSE_CLICK_BEFORE_BASE|PACK_RESUME_REQUIRES_PLACE_ONLY)
      printf 'boolean\n'
      ;;
    *)
      printf 'string\n'
      ;;
  esac
}

__timing_validate_value() {
  local name="$1"
  local value="$2"
  local kind

  kind="$(__timing_value_kind "$name")"

  case "$kind" in
    duration)
      parse_duration_ms "$value" >/dev/null 2>&1
      ;;
    integer)
      [[ "$value" =~ ^[0-9]+$ ]]
      ;;
    boolean)
      [[ "$value" =~ ^(0|1)$ ]]
      ;;
    string)
      test -n "$value"
      ;;
  esac
}

timing_validate_required() {
  local required_file="${1:-}"
  local raw
  local name
  local value
  local kind
  local ms
  local failures=0

  if test -z "$required_file" || ! test -f "$required_file"; then
    printf 'ERROR: required timing file not found: %s\n' "$required_file" >&2
    return 2
  fi

  while IFS= read -r raw || test -n "$raw"; do
    name="${raw%%#*}"
    name="$(__trim "$name")"

    if test -z "$name"; then
      continue
    fi

    if test -z "${__timing_seen[$name]+x}"; then
      printf 'MISSING: timing %s\n' "$name"
      failures=$((failures + 1))
      continue
    fi

    value="${__timing_values[$name]}"
    if test -z "$value" || test "$value" = "unset"; then
      printf 'UNSET: timing %s\n' "$name"
      failures=$((failures + 1))
      continue
    fi

    kind="$(__timing_value_kind "$name")"
    if __timing_validate_value "$name" "$value"; then
      if test "$kind" = "duration"; then
        ms="$(parse_duration_ms "$value")"
        printf 'OK: timing %s = %s (%sms)\n' "$name" "$value" "$ms"
      else
        printf 'OK: timing %s = %s\n' "$name" "$value"
      fi
    else
      printf 'INVALID: timing %s = %s expected %s\n' "$name" "$value" "$kind"
      failures=$((failures + 1))
    fi
  done < "$required_file"

  test "$failures" -eq 0
}
