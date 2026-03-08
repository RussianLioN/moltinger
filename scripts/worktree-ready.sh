#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/worktree-ready.sh <mode> [options]

Modes:
  create    Prepare a new worktree flow for a new or derived branch
  attach    Prepare a worktree flow for an existing branch
  doctor    Diagnose readiness for an existing worktree
  handoff   Render or execute a handoff profile for a prepared worktree

Common Options:
  --branch <name>            Target git branch
  --path <path>              Explicit worktree path override
  --repo <path>              Repository root override
  --handoff <profile>        Handoff profile (manual|terminal|codex)
  --existing <branch>        Existing branch hint for create flows
  -h, --help                 Show this help

Examples:
  scripts/worktree-ready.sh create --branch 005-worktree-ready-flow
  scripts/worktree-ready.sh attach --branch codex/gitops-metrics-fix
  scripts/worktree-ready.sh doctor --path ../moltinger-0308-005-worktree-ready-flow
  scripts/worktree-ready.sh handoff --handoff codex --path ../moltinger-0308-005-worktree-ready-flow
EOF
}

log() {
  echo "[worktree-ready] $*"
}

debug() {
  if [[ "${WORKTREE_READY_DEBUG:-0}" == "1" ]]; then
    echo "[worktree-ready] $*" >&2
  fi
}

warn() {
  echo "[worktree-ready] $*" >&2
}

die() {
  warn "$*"
  exit 2
}

not_implemented() {
  local feature="$1"
  warn "${feature} is not implemented yet."
  exit 1
}

mode=""
branch=""
target_path=""
repo_root=""
handoff_profile="manual"
existing_branch=""
path_preview=""
resolved_repo_root=""
resolved_common_dir=""
canonical_repo_name=""

report_worktree_path=""
report_path_preview=""
report_branch_name=""
report_issue_id=""
report_status="action_required"
report_env_state="unknown"
report_guard_state="unknown"
report_beads_state="missing"
report_handoff_mode="manual"

declare -a report_next_steps=()
declare -a report_warnings=()

discovered_worktree_name=""
discovered_worktree_path=""
discovered_branch_name=""
discovered_beads_state=""
discovered_redirect_target=""

guard_probe_path=""
guard_state_file=""
guard_expected_branch=""
guard_expected_worktree=""
guard_created_at=""
guard_updated_at=""
guard_current_branch=""
guard_current_worktree=""
guard_raw_status=""
guard_state="unknown"
branch_resolution_state="not_required"
environment_probe_path=""
environment_state="unknown"

parse_args() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      create|attach|doctor|handoff)
        if [[ -n "${mode}" ]]; then
          die "Mode already set to '${mode}', got extra mode '${1}'."
        fi
        mode="$1"
        shift
        ;;
      --branch)
        branch="${2:-}"
        if [[ -z "${branch}" ]]; then
          die "--branch requires a value"
        fi
        shift 2
        ;;
      --path)
        target_path="${2:-}"
        if [[ -z "${target_path}" ]]; then
          die "--path requires a value"
        fi
        shift 2
        ;;
      --repo)
        repo_root="${2:-}"
        if [[ -z "${repo_root}" ]]; then
          die "--repo requires a value"
        fi
        shift 2
        ;;
      --handoff)
        handoff_profile="${2:-}"
        if [[ -z "${handoff_profile}" ]]; then
          die "--handoff requires a value"
        fi
        shift 2
        ;;
      --existing)
        existing_branch="${2:-}"
        if [[ -z "${existing_branch}" ]]; then
          die "--existing requires a value"
        fi
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [[ -z "${mode}" ]]; then
          die "Unknown mode: $1"
        fi
        die "Unknown argument: $1"
        ;;
    esac
  done

  if [[ -z "${mode}" ]]; then
    usage >&2
    exit 2
  fi
}

normalize_path() {
  local input_path="$1"
  local base_path="${2:-$PWD}"
  local combined_path=""
  local part=""
  local -a path_parts=()
  local -a normalized_parts=()

  if [[ -z "${input_path}" ]]; then
    die "Path value is required"
  fi

  if [[ "${base_path}" != /* ]]; then
    die "Base path must be absolute: ${base_path}"
  fi

  if [[ "${input_path}" == /* ]]; then
    combined_path="${input_path}"
  else
    combined_path="${base_path%/}/${input_path}"
  fi

  IFS='/' read -r -a path_parts <<< "${combined_path}"
  for part in "${path_parts[@]}"; do
    case "${part}" in
      ""|".")
        continue
        ;;
      "..")
        if ((${#normalized_parts[@]} > 0)); then
          unset 'normalized_parts[${#normalized_parts[@]}-1]'
        fi
        ;;
      *)
        normalized_parts+=("${part}")
        ;;
    esac
  done

  if ((${#normalized_parts[@]} == 0)); then
    printf '/\n'
    return 0
  fi

  printf '/'
  local index=0
  for index in "${!normalized_parts[@]}"; do
    if [[ "${index}" -gt 0 ]]; then
      printf '/'
    fi
    printf '%s' "${normalized_parts[$index]}"
  done
  printf '\n'
}

sanitize_branch_name() {
  local raw_branch="$1"
  local sanitized=""

  if [[ -z "${raw_branch}" ]]; then
    die "Branch name is required for path formatting"
  fi

  raw_branch="${raw_branch#refs/heads/}"
  sanitized="$(printf '%s' "${raw_branch}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"

  if [[ -z "${sanitized}" ]]; then
    sanitized="worktree"
  fi

  printf '%s\n' "${sanitized}"
}

format_worktree_dirname() {
  local branch_name="$1"

  printf '%s-%s\n' "${canonical_repo_name}" "$(sanitize_branch_name "${branch_name}")"
}

format_path_preview() {
  local branch_name="$1"

  printf '../%s\n' "$(format_worktree_dirname "${branch_name}")"
}

resolve_explicit_path() {
  local candidate_path="$1"

  target_path="$(normalize_path "${candidate_path}" "${resolved_repo_root}")"
  path_preview="${target_path}"
}

derive_sibling_worktree_path() {
  local branch_name="$1"

  path_preview="$(format_path_preview "${branch_name}")"
  target_path="$(normalize_path "${path_preview}" "${resolved_repo_root}")"
}

resolve_repo_root() {
  local candidate_root=""
  local detected_root=""
  local detected_common_dir=""

  if [[ -n "${repo_root}" ]]; then
    candidate_root="$(normalize_path "${repo_root}" "$PWD")"
  else
    candidate_root="$PWD"
  fi

  if ! detected_root="$(git -C "${candidate_root}" rev-parse --show-toplevel 2>/dev/null)"; then
    die "Not inside a git repository: ${candidate_root}"
  fi

  resolved_repo_root="$(normalize_path "${detected_root}" "/")"
  detected_common_dir="$(git -C "${resolved_repo_root}" rev-parse --git-common-dir 2>/dev/null || printf '.git')"
  resolved_common_dir="$(normalize_path "${detected_common_dir}" "${resolved_repo_root}")"
  if [[ "$(basename "${resolved_common_dir}")" == ".git" ]]; then
    canonical_repo_name="$(basename "$(dirname "${resolved_common_dir}")")"
  else
    canonical_repo_name="$(basename "${resolved_repo_root}")"
  fi
  repo_root="${resolved_repo_root}"
  printf '%s\n' "${resolved_repo_root}"
}

require_git_repo() {
  resolve_repo_root >/dev/null
}

resolve_current_branch() {
  local current_branch=""

  if ! current_branch="$(git -C "${resolved_repo_root}" branch --show-current 2>/dev/null)"; then
    printf '\n'
    return 0
  fi

  printf '%s\n' "${current_branch}"
}

shell_quote() {
  printf '%q' "$1"
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    die "Required command not found: ${command_name}"
  fi
}

reset_discovery() {
  discovered_worktree_name=""
  discovered_worktree_path=""
  discovered_branch_name=""
  discovered_beads_state=""
  discovered_redirect_target=""
}

reset_guard_probe() {
  guard_probe_path=""
  guard_state_file=""
  guard_expected_branch=""
  guard_expected_worktree=""
  guard_created_at=""
  guard_updated_at=""
  guard_current_branch=""
  guard_current_worktree=""
  guard_raw_status=""
  guard_state="unknown"
}

resolve_existing_branch_state() {
  branch_resolution_state="missing"

  if [[ -z "${branch}" ]]; then
    return 1
  fi

  if git -C "${resolved_repo_root}" show-ref --verify --quiet "refs/heads/${branch}"; then
    branch_resolution_state="resolved"
    return 0
  fi

  return 1
}

reset_environment_probe() {
  environment_probe_path=""
  environment_state="unknown"
}

map_bd_beads_state() {
  local raw_state="$1"

  case "${raw_state}" in
    shared)
      printf 'shared\n'
      ;;
    redirect)
      printf 'redirected\n'
      ;;
    local|none|"")
      printf 'missing\n'
      ;;
    *)
      printf 'missing\n'
      ;;
  esac
}

iter_git_worktrees() {
  local line=""
  local current_path=""
  local current_branch=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      worktree\ *)
        current_path="$(normalize_path "${line#worktree }" "/")"
        current_branch=""
        ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        ;;
      "")
        if [[ -n "${current_path}" ]]; then
          printf '%s\t%s\n' "${current_path}" "${current_branch}"
        fi
        current_path=""
        current_branch=""
        ;;
    esac
  done < <(git -C "${resolved_repo_root}" worktree list --porcelain)

  if [[ -n "${current_path}" ]]; then
    printf '%s\t%s\n' "${current_path}" "${current_branch}"
  fi
}

find_git_worktree_by_branch() {
  local search_branch="$1"
  local worktree_path=""
  local worktree_branch=""

  while IFS=$'\t' read -r worktree_path worktree_branch; do
    if [[ "${worktree_branch}" == "${search_branch}" ]]; then
      printf '%s\t%s\n' "${worktree_path}" "${worktree_branch}"
      return 0
    fi
  done < <(iter_git_worktrees)

  return 1
}

find_git_worktree_by_path() {
  local search_path="$1"
  local normalized_search_path=""
  local worktree_path=""
  local worktree_branch=""

  normalized_search_path="$(normalize_path "${search_path}" "${resolved_repo_root}")"

  while IFS=$'\t' read -r worktree_path worktree_branch; do
    if [[ "${worktree_path}" == "${normalized_search_path}" ]]; then
      printf '%s\t%s\n' "${worktree_path}" "${worktree_branch}"
      return 0
    fi
  done < <(iter_git_worktrees)

  return 1
}

find_bd_worktree_by_path() {
  local search_path="$1"
  local normalized_search_path=""

  require_command jq
  normalized_search_path="$(normalize_path "${search_path}" "${resolved_repo_root}")"

  bd worktree list --json \
    | jq -r --arg path "${normalized_search_path}" '
        .[]
        | select(.path == $path)
        | [(.name // ""), (.path // ""), (.branch // ""), (.beads_state // ""), (.redirect_to // "")]
        | @tsv
      '
}

discover_target_state() {
  local git_record=""
  local bd_record=""
  local bd_path=""
  local git_path=""
  local git_branch=""
  local bd_name=""
  local bd_branch=""
  local bd_state=""
  local bd_redirect=""

  reset_discovery

  if [[ -n "${target_path}" ]]; then
    git_record="$(find_git_worktree_by_path "${target_path}" || true)"
  fi

  if [[ -z "${git_record}" && -n "${branch}" ]]; then
    git_record="$(find_git_worktree_by_branch "${branch}" || true)"
  fi

  if [[ -n "${git_record}" ]]; then
    IFS=$'\t' read -r git_path git_branch <<< "${git_record}"
    discovered_worktree_path="${git_path}"
    discovered_branch_name="${git_branch}"
  fi

  if [[ -n "${discovered_worktree_path}" ]]; then
    bd_record="$(find_bd_worktree_by_path "${discovered_worktree_path}" || true)"
  elif [[ -n "${target_path}" ]]; then
    bd_record="$(find_bd_worktree_by_path "${target_path}" || true)"
  fi

  if [[ -n "${bd_record}" ]]; then
    IFS=$'\t' read -r bd_name bd_path bd_branch bd_state bd_redirect <<< "${bd_record}"
    discovered_worktree_name="${bd_name}"
    if [[ -z "${discovered_worktree_path}" ]]; then
      discovered_worktree_path="${bd_path}"
    fi
    if [[ -z "${discovered_branch_name}" ]]; then
      discovered_branch_name="${bd_branch}"
    fi
    discovered_beads_state="$(map_bd_beads_state "${bd_state}")"
    discovered_redirect_target="${bd_redirect}"
  fi
}

resolve_guard_probe_path() {
  if [[ -n "${discovered_worktree_path}" && -d "${discovered_worktree_path}" ]]; then
    printf '%s\n' "${discovered_worktree_path}"
    return 0
  fi

  if [[ -n "${target_path}" && -d "${target_path}" ]]; then
    printf '%s\n' "${target_path}"
    return 0
  fi

  return 1
}

parse_guard_probe_output() {
  local output="$1"
  local line=""
  local key=""
  local value=""

  while IFS= read -r line; do
    case "${line}" in
      *=*)
        key="${line%%=*}"
        value="${line#*=}"
        ;;
      *)
        continue
        ;;
    esac

    case "${key}" in
      state_file) guard_state_file="${value}" ;;
      expected_branch) guard_expected_branch="${value}" ;;
      expected_worktree) guard_expected_worktree="${value}" ;;
      created_at) guard_created_at="${value}" ;;
      updated_at) guard_updated_at="${value}" ;;
      current_branch) guard_current_branch="${value}" ;;
      current_worktree) guard_current_worktree="${value}" ;;
      status) guard_raw_status="${value}" ;;
    esac
  done <<< "${output}"

  case "${guard_raw_status}" in
    ok)
      guard_state="ok"
      ;;
    drift|detached_head)
      guard_state="drift"
      ;;
    "")
      if [[ "${output}" == *"No guard state yet"* ]]; then
        guard_state="missing"
      fi
      ;;
    *)
      guard_state="unknown"
      ;;
  esac
}

discover_guard_state() {
  local output=""
  local exit_code=0

  reset_guard_probe

  if ! guard_probe_path="$(resolve_guard_probe_path)"; then
    return 0
  fi

  if [[ ! -x "${guard_probe_path}/scripts/git-session-guard.sh" ]]; then
    guard_state="missing"
    return 0
  fi

  set +e
  output="$(
    cd "${guard_probe_path}" && ./scripts/git-session-guard.sh --status 2>&1
  )"
  exit_code=$?
  set -e

  parse_guard_probe_output "${output}"

  if [[ -z "${guard_raw_status}" && "${exit_code}" -ne 0 ]]; then
    guard_state="unknown"
  fi
}

resolve_environment_probe_path() {
  if [[ -n "${discovered_worktree_path}" && -d "${discovered_worktree_path}" ]]; then
    printf '%s\n' "${discovered_worktree_path}"
    return 0
  fi

  if [[ -n "${target_path}" && -d "${target_path}" ]]; then
    printf '%s\n' "${target_path}"
    return 0
  fi

  return 1
}

discover_environment_state() {
  local output=""
  local exit_code=0

  reset_environment_probe

  if ! environment_probe_path="$(resolve_environment_probe_path)"; then
    return 0
  fi

  if [[ ! -f "${environment_probe_path}/.envrc" ]]; then
    environment_state="no_envrc"
    return 0
  fi

  if ! command -v direnv >/dev/null 2>&1; then
    environment_state="unknown"
    return 0
  fi

  set +e
  output="$(
    cd "${environment_probe_path}" && direnv export json 2>&1
  )"
  exit_code=$?
  set -e

  if [[ "${exit_code}" -eq 0 ]]; then
    environment_state="approved_or_not_required"
    return 0
  fi

  if [[ "${output}" == *"is blocked. Run `direnv allow` to approve its content"* ]]; then
    environment_state="approval_needed"
    return 0
  fi

  environment_state="unknown"
}

reset_report() {
  report_worktree_path=""
  report_path_preview=""
  report_branch_name=""
  report_issue_id=""
  report_status="action_required"
  report_env_state="unknown"
  report_guard_state="unknown"
  report_beads_state="missing"
  report_handoff_mode="${handoff_profile}"
  report_next_steps=()
  report_warnings=()
}

set_report_target() {
  report_worktree_path="${target_path:-n/a}"
  report_path_preview="${path_preview:-n/a}"
  report_branch_name="${branch:-n/a}"
}

apply_discovery_to_report() {
  if [[ "${branch_resolution_state}" == "resolved" && -n "${discovered_worktree_path}" ]]; then
    report_worktree_path="${discovered_worktree_path}"
  elif [[ -n "${discovered_worktree_path}" && "${discovered_worktree_path}" == "${target_path}" ]]; then
    report_worktree_path="${discovered_worktree_path}"
  fi

  if [[ -n "${discovered_branch_name}" && "${report_branch_name}" == "n/a" ]]; then
    report_branch_name="${discovered_branch_name}"
  fi

  if [[ -n "${discovered_beads_state}" ]]; then
    report_beads_state="${discovered_beads_state}"
  fi

  if [[ -n "${discovered_worktree_path}" && -n "${target_path}" && "${discovered_worktree_path}" != "${target_path}" ]]; then
    if [[ "${branch_resolution_state}" == "resolved" ]]; then
      add_warning "Branch '${report_branch_name}' is already attached at ${discovered_worktree_path}"
    else
      add_warning "Discovery found an existing worktree at ${discovered_worktree_path}"
    fi
  fi

  if [[ -n "${discovered_redirect_target}" ]]; then
    add_warning "Discovery found beads redirect metadata for the target worktree"
  fi
}

apply_guard_probe_to_report() {
  if [[ -n "${guard_state}" ]]; then
    report_guard_state="${guard_state}"
  fi

  if [[ "${guard_state}" == "drift" ]]; then
    add_warning "Guard probe detected branch/worktree drift for the target"
  fi

  if [[ "${guard_state}" == "missing" ]]; then
    add_warning "Guard probe found no session guard state for the target"
  fi
}

apply_branch_resolution_to_report() {
  if [[ "${branch_resolution_state}" == "missing" ]]; then
    add_warning "Existing branch '${branch}' is not available locally."
  fi
}

apply_environment_probe_to_report() {
  report_env_state="${environment_state}"

  if [[ "${environment_state}" == "approval_needed" ]]; then
    add_warning "Environment approval is required before launching the session."
  fi
}

target_path_exists() {
  [[ -n "${target_path}" && -d "${target_path}" ]]
}

report_worktree_path_exists() {
  [[ -n "${report_worktree_path}" && "${report_worktree_path}" != "n/a" && -d "${report_worktree_path}" ]]
}

set_readiness_status() {
  if [[ "${branch_resolution_state}" == "missing" ]]; then
    report_status="action_required"
    return 0
  fi

  if [[ "${report_guard_state}" == "drift" ]]; then
    report_status="drift_detected"
    return 0
  fi

  if report_worktree_path_exists; then
    if [[ "${report_beads_state}" == "missing" && -n "${discovered_worktree_path}" ]]; then
      report_status="action_required"
      add_warning "The target worktree exists, but shared beads configuration could not be confirmed."
      return 0
    fi

    case "${report_env_state}" in
      approval_needed)
        report_status="needs_env_approval"
        ;;
      approved_or_not_required|no_envrc)
        report_status="ready_for_codex"
        ;;
      *)
        report_status="created"
        ;;
    esac
    return 0
  fi

  report_status="action_required"
}

set_readiness_next_steps() {
  local mode_name="$1"

  if [[ "${branch_resolution_state}" == "missing" ]]; then
    add_next_step "Create or fetch the branch '${branch}' before using attach or start --existing"
    return 0
  fi

  case "${report_status}" in
    drift_detected)
      if [[ "${report_worktree_path}" != "n/a" ]]; then
        add_next_step "cd $(shell_quote "${report_worktree_path}")"
      fi
      add_next_step "./scripts/git-session-guard.sh --refresh"
      ;;
    ready_for_codex)
      add_next_step "cd $(shell_quote "${report_worktree_path}") && codex"
      ;;
    needs_env_approval)
      add_next_step "cd $(shell_quote "${report_worktree_path}") && direnv allow"
      add_next_step "codex"
      ;;
    created)
      add_next_step "cd $(shell_quote "${report_worktree_path}")"
      case "${report_env_state}" in
        approval_needed)
          add_next_step "direnv allow"
          ;;
        unknown)
          add_next_step "direnv allow # if prompted"
          ;;
      esac
      add_next_step "codex"
      ;;
    action_required)
      case "${mode_name}" in
        create|attach)
          if [[ -n "${discovered_worktree_path}" ]]; then
            add_next_step "cd $(shell_quote "${report_worktree_path}")"
            add_next_step "Inspect the existing worktree and fix the reported prerequisites"
          else
            add_next_step "bd worktree create $(shell_quote "${path_preview}") --branch $(shell_quote "${branch}")"
          fi
          ;;
        doctor|handoff)
          if [[ "${report_worktree_path}" != "n/a" ]]; then
            add_next_step "cd $(shell_quote "${report_worktree_path}")"
          fi
          add_next_step "Inspect the target and retry once prerequisites are fixed"
          ;;
        *)
          add_next_step "Inspect the target inputs and retry the command"
          ;;
      esac
      ;;
  esac
}

add_next_step() {
  local step_text="$1"

  if [[ -n "${step_text}" ]]; then
    report_next_steps+=("${step_text}")
  fi
}

add_warning() {
  local warning_text="$1"

  if [[ -n "${warning_text}" ]]; then
    report_warnings+=("${warning_text}")
  fi
}

render_numbered_list() {
  local item=""
  local index=1

  if [[ "$#" -eq 0 ]]; then
    printf '  1. none\n'
    return 0
  fi

  for item in "$@"; do
    printf '  %d. %s\n' "${index}" "${item}"
    index=$((index + 1))
  done
}

render_warning_list() {
  local warning_item=""

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  printf 'Warnings:\n'
  for warning_item in "$@"; do
    printf '  - %s\n' "${warning_item}"
  done
}

render_readiness_report() {
  printf 'Worktree: %s\n' "${report_worktree_path:-n/a}"
  printf 'Preview: %s\n' "${report_path_preview:-n/a}"
  printf 'Branch: %s\n' "${report_branch_name:-n/a}"
  printf 'Issue: %s\n' "${report_issue_id:-n/a}"
  printf 'Status: %s\n' "${report_status}"
  printf 'Env: %s\n' "${report_env_state}"
  printf 'Guard: %s\n' "${report_guard_state}"
  printf 'Beads: %s\n' "${report_beads_state}"
  printf 'Handoff: %s\n' "${report_handoff_mode}"
  printf 'Next:\n'
  render_numbered_list "${report_next_steps[@]}"
  render_warning_list "${report_warnings[@]}"
}

normalize_mode_inputs() {
  case "${handoff_profile}" in
    manual|terminal|codex)
      ;;
    *)
      die "Unsupported handoff profile: ${handoff_profile}"
      ;;
  esac
}

render_context_summary() {
  debug "mode=${mode}"
  debug "branch=${branch:-<unset>}"
  debug "path=${target_path:-<unset>}"
  debug "repo=${repo_root:-<auto>}"
  debug "handoff=${handoff_profile}"
  debug "existing=${existing_branch:-<unset>}"
}

prepare_report_target() {
  reset_report
  set_report_target
  apply_discovery_to_report
  apply_guard_probe_to_report
  apply_branch_resolution_to_report
  apply_environment_probe_to_report
}

render_mode_placeholder() {
  local mode_name="$1"

  prepare_report_target
  set_readiness_status
  set_readiness_next_steps "${mode_name}"

  if [[ "${report_env_state}" == "unknown" ]]; then
    add_warning "Environment readiness has not been probed yet."
  fi

  if [[ "${mode_name}" == "handoff" && "${handoff_profile}" != "manual" ]]; then
    add_warning "Automated terminal or Codex handoff is not implemented until T017-T018."
  fi

  render_readiness_report
}

prepare_create_context() {
  require_git_repo
  branch_resolution_state="not_required"

  if [[ -z "${branch}" ]]; then
    branch="${existing_branch:-}"
  fi

  if [[ -z "${branch}" ]]; then
    die "create mode requires --branch or --existing"
  fi

  if [[ -n "${existing_branch}" ]]; then
    resolve_existing_branch_state || true
  fi

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  else
    derive_sibling_worktree_path "${branch}"
  fi

  discover_target_state
  discover_guard_state
  discover_environment_state
}

prepare_attach_context() {
  require_git_repo
  branch_resolution_state="not_required"

  if [[ -z "${branch}" ]]; then
    die "attach mode requires --branch"
  fi

  resolve_existing_branch_state || true

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  else
    derive_sibling_worktree_path "${branch}"
  fi

  discover_target_state
  discover_guard_state
  discover_environment_state
}

prepare_doctor_context() {
  require_git_repo
  branch_resolution_state="not_required"

  if [[ -z "${branch}" && -z "${target_path}" ]]; then
    branch="$(resolve_current_branch)"
  fi

  if [[ -n "${branch}" ]]; then
    resolve_existing_branch_state || true
  fi

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  elif [[ -n "${branch}" ]]; then
    derive_sibling_worktree_path "${branch}"
  else
    target_path="${resolved_repo_root}"
    path_preview="${resolved_repo_root}"
  fi

  discover_target_state
  discover_guard_state
  discover_environment_state
}

prepare_handoff_context() {
  require_git_repo
  branch_resolution_state="not_required"

  if [[ -z "${branch}" && -z "${target_path}" ]]; then
    branch="$(resolve_current_branch)"
  fi

  if [[ -n "${branch}" ]]; then
    resolve_existing_branch_state || true
  fi

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  elif [[ -n "${branch}" ]]; then
    derive_sibling_worktree_path "${branch}"
  else
    die "handoff mode requires --path or a branch context"
  fi

  discover_target_state
  discover_guard_state
  discover_environment_state
}

handle_create() {
  prepare_create_context
  render_mode_placeholder "create"
}

handle_attach() {
  prepare_attach_context
  render_mode_placeholder "attach"
}

handle_doctor() {
  prepare_doctor_context
  render_mode_placeholder "doctor"
}

handle_handoff() {
  prepare_handoff_context
  render_mode_placeholder "handoff"
}

main() {
  parse_args "$@"
  normalize_mode_inputs
  render_context_summary

  case "${mode}" in
    create)
      handle_create
      ;;
    attach)
      handle_attach
      ;;
    doctor)
      handle_doctor
      ;;
    handoff)
      handle_handoff
      ;;
    *)
      die "Unknown mode: ${mode}"
      ;;
  esac
}

main "$@"
