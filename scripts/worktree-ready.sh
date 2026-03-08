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
}

render_mode_placeholder() {
  local mode_name="$1"

  prepare_report_target
  add_warning "Mode '${mode_name}' is still using placeholder readiness values until T005-T007 are implemented."

  case "${mode_name}" in
    create|attach)
      report_status="action_required"
      add_next_step "bd worktree create $(shell_quote "${path_preview}") --branch $(shell_quote "${branch}")"
      ;;
    doctor)
      report_status="action_required"
      add_next_step "Re-run doctor after discovery and readiness probes land in T005-T007"
      ;;
    handoff)
      report_status="action_required"
      add_next_step "Use manual handoff until T017-T018 implement terminal or Codex launch support"
      ;;
    *)
      report_status="action_required"
      add_next_step "Complete the remaining implementation tasks for ${mode_name}"
      ;;
  esac

  render_readiness_report
}

prepare_create_context() {
  require_git_repo

  if [[ -z "${branch}" ]]; then
    branch="${existing_branch:-}"
  fi

  if [[ -z "${branch}" ]]; then
    die "create mode requires --branch or --existing"
  fi

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  else
    derive_sibling_worktree_path "${branch}"
  fi
}

prepare_attach_context() {
  require_git_repo

  if [[ -z "${branch}" ]]; then
    die "attach mode requires --branch"
  fi

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  else
    derive_sibling_worktree_path "${branch}"
  fi
}

prepare_doctor_context() {
  require_git_repo

  if [[ -z "${branch}" && -z "${target_path}" ]]; then
    branch="$(resolve_current_branch)"
  fi

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  elif [[ -n "${branch}" ]]; then
    derive_sibling_worktree_path "${branch}"
  else
    target_path="${resolved_repo_root}"
    path_preview="${resolved_repo_root}"
  fi
}

prepare_handoff_context() {
  require_git_repo

  if [[ -z "${branch}" && -z "${target_path}" ]]; then
    branch="$(resolve_current_branch)"
  fi

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  elif [[ -n "${branch}" ]]; then
    derive_sibling_worktree_path "${branch}"
  else
    die "handoff mode requires --path or a branch context"
  fi
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
