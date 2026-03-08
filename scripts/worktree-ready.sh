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

resolve_repo_root() {
  if [[ -n "${repo_root}" ]]; then
    printf '%s\n' "${repo_root}"
    return 0
  fi

  not_implemented "Repository root discovery"
}

require_git_repo() {
  if [[ -n "${repo_root}" ]]; then
    return 0
  fi

  not_implemented "Git repository validation"
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
  log "mode=${mode}"
  log "branch=${branch:-<unset>}"
  log "path=${target_path:-<unset>}"
  log "repo=${repo_root:-<auto>}"
  log "handoff=${handoff_profile}"
  log "existing=${existing_branch:-<unset>}"
}

prepare_create_context() {
  require_git_repo
  not_implemented "Create context preparation"
}

prepare_attach_context() {
  require_git_repo
  not_implemented "Attach context preparation"
}

prepare_doctor_context() {
  require_git_repo
  not_implemented "Doctor context preparation"
}

prepare_handoff_context() {
  require_git_repo
  not_implemented "Handoff context preparation"
}

handle_create() {
  prepare_create_context
  not_implemented "Create mode"
}

handle_attach() {
  prepare_attach_context
  not_implemented "Attach mode"
}

handle_doctor() {
  prepare_doctor_context
  not_implemented "Doctor mode"
}

handle_handoff() {
  prepare_handoff_context
  not_implemented "Handoff mode"
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
