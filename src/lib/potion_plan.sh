#!/usr/bin/env bash

potion_plan_lib_dir="${BASH_SOURCE[0]%/*}"
if test "$potion_plan_lib_dir" = "${BASH_SOURCE[0]}"; then
  potion_plan_lib_dir="."
fi

# shellcheck source=timing.sh
. "$potion_plan_lib_dir/timing.sh"

declare -A __potion_plan_values=()
declare -A __potion_plan_seen=()
declare -a __potion_plan_names=()

__potion_plan_trim() {
  local value="$1"

  while [[ "$value" =~ ^[[:space:]] ]]; do
    value="${value:1}"
  done

  while [[ "$value" =~ [[:space:]]$ ]]; do
    value="${value:0:${#value}-1}"
  done

  printf '%s\n' "$value"
}

__potion_plan_unquote() {
  local value="$1"

  if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s\n' "$value"
}

__potion_plan_record_name() {
  local name="$1"

  if test -z "${__potion_plan_seen[$name]+x}"; then
    __potion_plan_seen["$name"]=1
    __potion_plan_names+=("$name")
  fi
}

__potion_plan_normalize_tier() {
  local tier="${1:-}"

  case "$tier" in
    2|2_MIN|POTION_2_MIN)
      printf '2_MIN\n'
      ;;
    6|6_MIN|POTION_6_MIN)
      printf '6_MIN\n'
      ;;
    15|15_MIN|POTION_15_MIN)
      printf '15_MIN\n'
      ;;
    *)
      printf 'ERROR: unknown potion tier: %s\n' "$tier" >&2
      return 2
      ;;
  esac
}

__potion_plan_point_is_set() {
  local name="$1"

  if ! declare -F points_is_set >/dev/null 2>&1; then
    printf 'ERROR: points_is_set is not loaded; source points.sh before point preflight\n' >&2
    return 2
  fi

  points_is_set "$name"
}

__potion_plan_10x_point_available() {
  local tier="$1"

  if __potion_plan_point_is_set "POTION_${tier}_USE_10X_BUTTON"; then
    return 0
  fi

  if test "$tier" = "2_MIN" && __potion_plan_point_is_set "USE_10X_BUTTON"; then
    return 0
  fi

  return 1
}

__potion_plan_10x_fallback() {
  local tier="$1"

  if test "$tier" = "2_MIN" &&
    ! __potion_plan_point_is_set "POTION_2_MIN_USE_10X_BUTTON" &&
    __potion_plan_point_is_set "USE_10X_BUTTON"; then
    printf 'USE_10X_BUTTON\n'
  fi
}

__potion_plan_preflight_points() {
  local tier
  local plan_enabled
  local enabled
  local amount
  local decomposed
  local ten_x_clicks
  local single_clicks
  local any_active=0
  local failures=0

  if ! declare -F points_is_set >/dev/null 2>&1; then
    printf 'ERROR: points library is not loaded\n' >&2
    return 2
  fi

  plan_enabled="$(potion_plan_get_bool POTION_PLAN_ENABLED)" || return 2
  if test "$plan_enabled" != "1"; then
    return 0
  fi

  for tier in 2_MIN 6_MIN 15_MIN; do
    enabled="$(potion_plan_tier_enabled "$tier")" || return 2
    amount="$(potion_plan_tier_use_amount "$tier")" || return 2

    if test "$enabled" != "1" || test "$amount" -eq 0; then
      continue
    fi

    any_active=1
    decomposed="$(potion_plan_decompose_amount "$amount")" || return 2
    ten_x_clicks="${decomposed%% *}"
    single_clicks="${decomposed#* }"

    if ! __potion_plan_point_is_set MENU_BUTTON; then
      printf 'ERROR: required menu point unavailable: MENU_BUTTON\n' >&2
      failures=$((failures + 1))
    fi

    if ! __potion_plan_point_is_set "POTION_${tier}"; then
      printf 'ERROR: required potion tier point unavailable: POTION_%s\n' "$tier" >&2
      failures=$((failures + 1))
    fi

    if test "$ten_x_clicks" -gt 0 && ! __potion_plan_10x_point_available "$tier"; then
      printf 'ERROR: required 10x point unavailable: POTION_%s_USE_10X_BUTTON\n' "$tier" >&2
      failures=$((failures + 1))
    fi

    if test "$single_clicks" -gt 0 && ! __potion_plan_point_is_set "POTION_${tier}_USE_SINGLE_BUTTON"; then
      printf 'ERROR: required single-use point unavailable: POTION_%s_USE_SINGLE_BUTTON\n' "$tier" >&2
      failures=$((failures + 1))
    fi
  done

  if test "$any_active" = "1" &&
    test "$(potion_plan_get_bool CLOSE_INVENTORY)" = "1" &&
    ! __potion_plan_point_is_set CLOSE_BUTTON; then
    printf 'ERROR: required close point unavailable: CLOSE_BUTTON\n' >&2
    failures=$((failures + 1))
  fi

  test "$failures" -eq 0
}

potion_plan_load() {
  local file="${1:-}"
  local raw
  local line
  local key
  local value

  if test -z "$file" || ! test -f "$file"; then
    printf 'ERROR: potion plan file not found: %s\n' "$file" >&2
    return 2
  fi

  __potion_plan_values=()
  __potion_plan_seen=()
  __potion_plan_names=()

  while IFS= read -r raw || test -n "$raw"; do
    line="${raw%%#*}"
    line="$(__potion_plan_trim "$line")"

    if test -z "$line"; then
      continue
    fi

    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="$(__potion_plan_trim "${BASH_REMATCH[2]}")"
      value="$(__potion_plan_unquote "$value")"
      __potion_plan_record_name "$key"
      __potion_plan_values["$key"]="$value"
      continue
    fi

    printf 'ERROR: invalid potion plan line: %s\n' "$raw" >&2
    return 2
  done < "$file"
}

potion_plan_get() {
  local key="${1:-}"

  if test -z "$key"; then
    printf 'ERROR: potion_plan_get requires a key\n' >&2
    return 2
  fi

  if test -z "${__potion_plan_seen[$key]+x}"; then
    printf 'ERROR: potion plan missing: %s\n' "$key" >&2
    return 1
  fi

  printf '%s\n' "${__potion_plan_values[$key]}"
}

potion_plan_get_bool() {
  local key="${1:-}"
  local value

  value="$(potion_plan_get "$key")" || return $?
  if ! [[ "$value" =~ ^(0|1)$ ]]; then
    printf 'ERROR: potion plan %s must be 0 or 1: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf '%s\n' "$value"
}

potion_plan_get_nonnegative_int() {
  local key="${1:-}"
  local value

  value="$(potion_plan_get "$key")" || return $?
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: potion plan %s must be a non-negative integer: %s\n' "$key" "$value" >&2
    return 2
  fi

  printf '%s\n' "$value"
}

potion_plan_get_duration() {
  local key="${1:-}"
  local value

  value="$(potion_plan_get "$key")" || return $?
  parse_duration_ms "$value" >/dev/null || return 2
  printf '%s\n' "$value"
}

potion_plan_decompose_amount() {
  local amount="${1:-}"

  if ! [[ "$amount" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: amount must be a non-negative integer: %s\n' "$amount" >&2
    return 2
  fi

  printf '%s %s\n' "$((amount / 10))" "$((amount % 10))"
}

potion_plan_tier_enabled() {
  local tier

  tier="$(__potion_plan_normalize_tier "${1:-}")" || return 2
  potion_plan_get_bool "POTION_${tier}_ENABLED"
}

potion_plan_tier_use_amount() {
  local tier

  tier="$(__potion_plan_normalize_tier "${1:-}")" || return 2
  potion_plan_get_nonnegative_int "POTION_${tier}_USE_AMOUNT"
}

potion_plan_tier_inventory() {
  local tier

  tier="$(__potion_plan_normalize_tier "${1:-}")" || return 2
  potion_plan_get_nonnegative_int "POTION_${tier}_INVENTORY"
}

potion_plan_validate() {
  local tier
  local value
  local ms
  local failures=0

  if value="$(potion_plan_get_bool POTION_PLAN_ENABLED)"; then
    printf 'OK: potion plan POTION_PLAN_ENABLED = %s\n' "$value"
  else
    failures=$((failures + 1))
  fi

  for tier in 2_MIN 6_MIN 15_MIN; do
    if value="$(potion_plan_tier_enabled "$tier")"; then
      printf 'OK: potion plan POTION_%s_ENABLED = %s\n' "$tier" "$value"
    else
      failures=$((failures + 1))
    fi

    if value="$(potion_plan_tier_use_amount "$tier")"; then
      printf 'OK: potion plan POTION_%s_USE_AMOUNT = %s\n' "$tier" "$value"
    else
      failures=$((failures + 1))
    fi

    if value="$(potion_plan_tier_inventory "$tier")"; then
      printf 'OK: potion plan POTION_%s_INVENTORY = %s\n' "$tier" "$value"
    else
      failures=$((failures + 1))
    fi
  done

  for value in POTION_NAV_CLICK_INTERVAL POTION_CLICK_INTERVAL; do
    if potion_plan_get_duration "$value" >/dev/null; then
      ms="$(parse_duration_ms "$(potion_plan_get "$value")")"
      printf 'OK: potion plan %s = %s (%sms)\n' "$value" "$(potion_plan_get "$value")" "$ms"
    else
      failures=$((failures + 1))
    fi
  done

  if value="$(potion_plan_get_bool CLOSE_INVENTORY)"; then
    printf 'OK: potion plan CLOSE_INVENTORY = %s\n' "$value"
  else
    failures=$((failures + 1))
  fi

  test "$failures" -eq 0
}

potion_plan_print() {
  local name
  local kind
  local ms

  for name in "${__potion_plan_names[@]}"; do
    case "$name" in
      *_INTERVAL)
        if ms="$(parse_duration_ms "${__potion_plan_values[$name]}" 2>/dev/null)"; then
          printf 'POTION_PLAN %s=%s ms=%s\n' "$name" "${__potion_plan_values[$name]}" "$ms"
        else
          printf 'POTION_PLAN %s=%s ms=invalid\n' "$name" "${__potion_plan_values[$name]}"
        fi
        ;;
      *_ENABLED|CLOSE_INVENTORY)
        kind="bool"
        printf 'POTION_PLAN %s=%s kind=%s\n' "$name" "${__potion_plan_values[$name]}" "$kind"
        ;;
      *_USE_AMOUNT|*_INVENTORY)
        kind="nonnegative_int"
        printf 'POTION_PLAN %s=%s kind=%s\n' "$name" "${__potion_plan_values[$name]}" "$kind"
        ;;
      *)
        printf 'POTION_PLAN %s=%s\n' "$name" "${__potion_plan_values[$name]}"
        ;;
    esac
  done
}

potion_plan_preflight_inventory() {
  local tier
  local plan_enabled
  local enabled
  local amount
  local inventory
  local projected
  local failures=0

  plan_enabled="$(potion_plan_get_bool POTION_PLAN_ENABLED)" || return 2
  if test "$plan_enabled" != "1"; then
    printf 'PREFLIGHT inventory potion_plan_enabled=0 skipped\n'
    return 0
  fi

  for tier in 2_MIN 6_MIN 15_MIN; do
    enabled="$(potion_plan_tier_enabled "$tier")" || return 2
    amount="$(potion_plan_tier_use_amount "$tier")" || return 2
    inventory="$(potion_plan_tier_inventory "$tier")" || return 2

    if test "$enabled" != "1" || test "$amount" -eq 0; then
      printf 'PREFLIGHT inventory tier=%s enabled=%s amount=%s inventory=%s skipped\n' "$tier" "$enabled" "$amount" "$inventory"
      continue
    fi

    projected=$((inventory - amount))
    if test "$projected" -lt 0; then
      printf 'FAIL: inventory tier=%s amount=%s inventory=%s projected_inventory=%s\n' "$tier" "$amount" "$inventory" "$projected" >&2
      failures=$((failures + 1))
    else
      printf 'OK: inventory tier=%s amount=%s inventory=%s projected_inventory=%s\n' "$tier" "$amount" "$inventory" "$projected"
    fi
  done

  test "$failures" -eq 0
}

potion_plan_project_inventory() {
  local tier="${1:-}"
  local normalized
  local enabled
  local amount
  local inventory

  if test -n "$tier"; then
    normalized="$(__potion_plan_normalize_tier "$tier")" || return 2
    amount="$(potion_plan_tier_use_amount "$normalized")" || return 2
    inventory="$(potion_plan_tier_inventory "$normalized")" || return 2
    printf '%s\n' "$((inventory - amount))"
    return 0
  fi

  for normalized in 2_MIN 6_MIN 15_MIN; do
    enabled="$(potion_plan_tier_enabled "$normalized")" || return 2
    amount="$(potion_plan_tier_use_amount "$normalized")" || return 2
    inventory="$(potion_plan_tier_inventory "$normalized")" || return 2
    printf 'PROJECTED tier=%s enabled=%s inventory=%s amount=%s projected_inventory=%s\n' "$normalized" "$enabled" "$inventory" "$amount" "$((inventory - amount))"
  done
}

potion_plan_print_click_plan() {
  local plan_enabled
  local tier
  local enabled
  local amount
  local inventory
  local projected
  local decomposed
  local ten_x_clicks
  local single_clicks
  local fallback
  local nav_interval
  local click_interval
  local close_inventory

  potion_plan_preflight_inventory >/dev/null || return $?
  __potion_plan_preflight_points || return $?

  plan_enabled="$(potion_plan_get_bool POTION_PLAN_ENABLED)" || return 2
  nav_interval="$(potion_plan_get_duration POTION_NAV_CLICK_INTERVAL)" || return 2
  click_interval="$(potion_plan_get_duration POTION_CLICK_INTERVAL)" || return 2
  close_inventory="$(potion_plan_get_bool CLOSE_INVENTORY)" || return 2

  printf 'TRACE potion-plan enabled=%s nav_click_interval=%s click_interval=%s close_inventory=%s\n' "$plan_enabled" "$nav_interval" "$click_interval" "$close_inventory"
  if test "$plan_enabled" != "1"; then
    printf 'TRACE potion-plan skipped enabled=0\n'
    return 0
  fi

  printf 'TRACE potion-plan open_inventory_button=MENU_BUTTON\n'
  for tier in 2_MIN 6_MIN 15_MIN; do
    enabled="$(potion_plan_tier_enabled "$tier")" || return 2
    amount="$(potion_plan_tier_use_amount "$tier")" || return 2
    inventory="$(potion_plan_tier_inventory "$tier")" || return 2

    if test "$enabled" != "1" || test "$amount" -eq 0; then
      printf 'TRACE potion-plan tier=%s skipped enabled=%s amount=%s\n' "$tier" "$enabled" "$amount"
      continue
    fi

    projected=$((inventory - amount))
    decomposed="$(potion_plan_decompose_amount "$amount")" || return 2
    ten_x_clicks="${decomposed%% *}"
    single_clicks="${decomposed#* }"

    printf 'TIER %s enabled=%s amount=%s inventory=%s projected_inventory=%s ten_x_clicks=%s single_clicks=%s\n' "$tier" "$enabled" "$amount" "$inventory" "$projected" "$ten_x_clicks" "$single_clicks"
    printf 'tier_button=POTION_%s\n' "$tier"
    printf 'ten_x_button=POTION_%s_USE_10X_BUTTON\n' "$tier"
    fallback="$(__potion_plan_10x_fallback "$tier")"
    if test -n "$fallback"; then
      printf 'ten_x_button_fallback=%s\n' "$fallback"
    fi
    printf 'single_button=POTION_%s_USE_SINGLE_BUTTON\n' "$tier"
  done

  if test "$close_inventory" = "1"; then
    printf 'TRACE potion-plan close_button=CLOSE_BUTTON\n'
  fi
}
