#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/beads-worktree-localize.sh [--path <worktree>]

Description:
  Localize Beads ownership for a git worktree by removing stale redirect metadata
  and bootstrapping a worktree-local SQLite DB from the checked-out JSONL state.
EOF
}

die() {
  echo "[beads-worktree-localize] $*" >&2
  exit 2
}

target_path=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        target_path="${2:-}"
        [[ -n "${target_path}" ]] || die "--path requires a value"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

normalize_path() {
  local input_path="$1"
  local base_path="${2:-$PWD}"

  if [[ "${input_path}" == /* ]]; then
    printf '%s\n' "${input_path}"
    return 0
  fi

  (
    cd "${base_path}"
    cd "${input_path}"
    pwd -P
  )
}

ensure_worktree_context() {
  if [[ -z "${target_path}" ]]; then
    target_path="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  else
    target_path="$(normalize_path "${target_path}")"
  fi

  [[ -n "${target_path}" ]] || die "Unable to resolve target worktree path"
  git -C "${target_path}" rev-parse --show-toplevel >/dev/null 2>&1 || die "Not a git worktree: ${target_path}"
}

localize_beads_state() {
  local beads_dir="${target_path}/.beads"
  local redirect_path="${beads_dir}/redirect"
  local local_db="${beads_dir}/beads.db"

  [[ -d "${beads_dir}" ]] || return 0

  if [[ -f "${redirect_path}" ]]; then
    [[ -f "${beads_dir}/config.yaml" ]] || die "Refusing to remove ${redirect_path} without ${beads_dir}/config.yaml"
    [[ -f "${beads_dir}/issues.jsonl" ]] || die "Refusing to remove ${redirect_path} without ${beads_dir}/issues.jsonl"
    rm -f "${redirect_path}"
  fi

  if [[ -f "${beads_dir}/config.yaml" && -f "${beads_dir}/issues.jsonl" ]]; then
    command -v bd >/dev/null 2>&1 || die "bd is required to bootstrap ${local_db}"
    (
      cd "${target_path}"
      BEADS_DB="${local_db}" bd --no-daemon list >/dev/null 2>&1
    )
  fi
}

report_state() {
  local beads_dir="${target_path}/.beads"
  local redirect_path="${beads_dir}/redirect"
  local local_db="${beads_dir}/beads.db"
  local ownership="missing"
  local redirect_state="absent"
  local db_state="absent"

  if [[ -d "${beads_dir}" ]]; then
    ownership="local"
  fi
  if [[ -f "${redirect_path}" ]]; then
    ownership="redirected"
    redirect_state="$(cat "${redirect_path}")"
  fi
  if [[ -f "${local_db}" ]]; then
    db_state="present"
  fi

  printf 'Worktree: %s\n' "${target_path}"
  printf 'Beads Dir: %s\n' "${beads_dir}"
  printf 'Ownership: %s\n' "${ownership}"
  printf 'Redirect: %s\n' "${redirect_state}"
  printf 'Local DB: %s\n' "${db_state}"
}

main() {
  parse_args "$@"
  ensure_worktree_context
  localize_beads_state
  report_state
}

main "$@"
