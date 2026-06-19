#!/usr/bin/env bash

config_lib_dir="${BASH_SOURCE[0]%/*}"
if test "$config_lib_dir" = "${BASH_SOURCE[0]}"; then
  config_lib_dir="."
fi

config_project_root() {
  local root="${MACRO_PROJECT_ROOT:-}"

  if test -n "$root"; then
    (cd "$root" && pwd -P)
    return
  fi

  (cd "$config_lib_dir/../.." && pwd -P)
}

config_runtime_dir() {
  printf '%s/runtime_config\n' "$(config_project_root)"
}

config_pack_opener_dir() {
  printf '%s/pack_opener\n' "$(config_runtime_dir)"
}

config_pack_opener_template_dir() {
  printf '%s/config_templates/pack_opener\n' "$(config_project_root)"
}

config_pack_opener_potion_plan_template() {
  printf '%s/potion_plan.conf\n' "$(config_pack_opener_template_dir)"
}

config_pack_opener_potion_plan_file() {
  printf '%s/potion_plan.conf\n' "$(config_pack_opener_dir)"
}

config_ensure_pack_opener_runtime() {
  mkdir -p "$(config_pack_opener_dir)"
}

config_bootstrap_pack_opener_from_templates() {
  local root
  local runtime_dir
  local template_dir
  local runtime_points
  local runtime_timing
  local runtime_potion_plan

  root="$(config_project_root)"
  runtime_dir="$(config_pack_opener_dir)"
  template_dir="$(config_pack_opener_template_dir)"
  runtime_points="$runtime_dir/points.conf"
  runtime_timing="$runtime_dir/timing.conf"
  runtime_potion_plan="$(config_pack_opener_potion_plan_file)"

  config_ensure_pack_opener_runtime

  if ! test -f "$runtime_points"; then
    cp "$template_dir/points.conf" "$runtime_points"
    printf 'BOOTSTRAP copied points.conf -> %s\n' "$runtime_points"
  else
    printf 'BOOTSTRAP kept existing %s\n' "$runtime_points"
  fi

  if ! test -f "$runtime_timing"; then
    cp "$template_dir/timing.conf" "$runtime_timing"
    printf 'BOOTSTRAP copied timing.conf -> %s\n' "$runtime_timing"
  else
    printf 'BOOTSTRAP kept existing %s\n' "$runtime_timing"
  fi

  if ! test -f "$runtime_potion_plan"; then
    cp "$template_dir/potion_plan.conf" "$runtime_potion_plan"
    printf 'BOOTSTRAP copied potion_plan.conf -> %s\n' "$runtime_potion_plan"
  else
    printf 'BOOTSTRAP kept existing %s\n' "$runtime_potion_plan"
  fi
}

config_market_buyer_dir() {
  printf '%s/market_buyer\n' "$(config_runtime_dir)"
}

config_market_buyer_template_dir() {
  printf '%s/config_templates/market_buyer\n' "$(config_project_root)"
}

config_figurines_buyer_dir() {
  printf '%s/figurines_buyer\n' "$(config_runtime_dir)"
}

config_figurines_buyer_template_dir() {
  printf '%s/config_templates/figurines_buyer\n' "$(config_project_root)"
}

config_star_trials_dir() {
  printf '%s/star_trials\n' "$(config_runtime_dir)"
}

config_star_trials_template_dir() {
  printf '%s/config_templates/star_trials\n' "$(config_project_root)"
}

config_orchestrator_dir() {
  printf '%s/orchestrator\n' "$(config_runtime_dir)"
}

config_orchestrator_template_dir() {
  printf '%s/config_templates/orchestrator\n' "$(config_project_root)"
}

config_bootstrap_buyer() {
  local buyer="$1"
  local runtime_dir template_dir
  runtime_dir="$(config_runtime_dir)/${buyer}"
  template_dir="$(config_project_root)/config_templates/${buyer}"
  mkdir -p "$runtime_dir"
  local f
  for f in defaults.conf points.conf; do
    if ! test -f "$runtime_dir/$f" && test -f "$template_dir/$f"; then
      cp "$template_dir/$f" "$runtime_dir/$f"
    fi
  done
}

config_recovery_dir() {
  printf '%s/recovery\n' "$(config_runtime_dir)"
}

config_recovery_template_dir() {
  printf '%s/config_templates/recovery\n' "$(config_project_root)"
}

config_event_voter_dir() {
  printf '%s/event_voter\n' "$(config_runtime_dir)"
}

config_event_voter_template_dir() {
  printf '%s/config_templates/event_voter\n' "$(config_project_root)"
}

config_sober_launcher_dir() {
  printf '%s/sober_launcher\n' "$(config_runtime_dir)"
}

config_sober_launcher_template_dir() {
  printf '%s/config_templates/sober_launcher\n' "$(config_project_root)"
}

config_sober_launcher_defaults_file() {
  printf '%s/defaults.conf\n' "$(config_sober_launcher_dir)"
}

config_print_pack_opener_paths() {
  local root
  local runtime_dir

  root="$(config_project_root)"
  runtime_dir="$(config_pack_opener_dir)"

  printf 'Project root: %s\n' "$root"
  printf 'Runtime config dir: %s\n' "$(config_runtime_dir)"
  printf 'Pack Opener config dir: %s\n' "$runtime_dir"
  printf 'Pack Opener points: %s/points.conf\n' "$runtime_dir"
  printf 'Pack Opener timing: %s/timing.conf\n' "$runtime_dir"
  printf 'Pack Opener potion plan: %s\n' "$(config_pack_opener_potion_plan_file)"
  printf 'Pack Opener required points: %s/config_templates/pack_opener/points.required\n' "$root"
  printf 'Pack Opener required timing: %s/config_templates/pack_opener/timing.required\n' "$root"
}
