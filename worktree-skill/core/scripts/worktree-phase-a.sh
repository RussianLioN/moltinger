#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/worktree-phase-a.sh create-from-base [options]

Options:
  --canonical-root <path>   Canonical root worktree on the default branch
  --base-ref <ref>          Base ref for the new branch (default: main)
  --branch <name>           Target branch to create or attach
  --path <path>             Target worktree path
  --format <kind>           Output format: human | env (default: human)
  -h, --help                Show this help
EOF
}

die() {
  echo "[worktree-phase-a] $*" >&2
  exit 2
}

render_env_kv() {
  local key="$1"
  local value="${2:-}"
  printf '%s=%q\n' "${key}" "${value}"
}

mode=""
canonical_root=""
base_ref="main"
branch=""
target_path=""
output_format="human"

parse_args() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi

  mode="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --canonical-root)
        canonical_root="${2:-}"
        shift 2
        ;;
      --base-ref)
        base_ref="${2:-}"
        shift 2
        ;;
      --branch)
        branch="${2:-}"
        shift 2
        ;;
      --path)
        target_path="${2:-}"
        shift 2
        ;;
      --format)
        output_format="${2:-}"
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

  [[ -n "${canonical_root}" ]] || die "--canonical-root is required"
  [[ -n "${branch}" ]] || die "--branch is required"
  [[ -n "${target_path}" ]] || die "--path is required"
  [[ "${canonical_root}" = /* ]] || die "--canonical-root must be absolute"
  [[ "${target_path}" = /* ]] || die "--path must be absolute"

  case "${output_format}" in
    human|env) ;;
    *) die "Unsupported output format: ${output_format}" ;;
  esac
}

ensure_prerequisites() {
  command -v git >/dev/null 2>&1 || die "git is required"
  [[ -d "${canonical_root}/.git" || -f "${canonical_root}/.git" ]] || die "Canonical root is not a git worktree: ${canonical_root}"
  [[ ! -e "${target_path}" ]] || die "Target worktree path already exists: ${target_path}"
  git -C "${canonical_root}" rev-parse --verify "${base_ref}^{commit}" >/dev/null 2>&1 || die "Base ref does not resolve to a commit: ${base_ref}"
}

render_success() {
  local base_sha="$1"
  local head_sha="$2"

  if [[ "${output_format}" == "env" ]]; then
    render_env_kv "schema" "worktree-phase-a/v1"
    render_env_kv "mode" "${mode}"
    render_env_kv "canonical_root" "${canonical_root}"
    render_env_kv "base_ref" "${base_ref}"
    render_env_kv "base_sha" "${base_sha}"
    render_env_kv "branch" "${branch}"
    render_env_kv "worktree" "${target_path}"
    render_env_kv "head_sha" "${head_sha}"
    render_env_kv "result" "created_from_base"
    return 0
  fi

  printf 'Mode: %s\n' "${mode}"
  printf 'Canonical Root: %s\n' "${canonical_root}"
  printf 'Base Ref: %s\n' "${base_ref}"
  printf 'Base SHA: %s\n' "${base_sha}"
  printf 'Branch: %s\n' "${branch}"
  printf 'Worktree: %s\n' "${target_path}"
  printf 'Head SHA: %s\n' "${head_sha}"
  printf 'Result: created_from_base\n'
}

create_from_base() {
  local base_sha=""
  local branch_exists=0
  local branch_sha=""
  local head_sha=""

  base_sha="$(git -C "${canonical_root}" rev-parse "${base_ref}^{commit}")"

  if git -C "${canonical_root}" show-ref --verify --quiet "refs/heads/${branch}"; then
    branch_exists=1
    branch_sha="$(git -C "${canonical_root}" rev-parse "${branch}^{commit}")"
    if [[ "${branch_sha}" != "${base_sha}" ]]; then
      echo "[worktree-phase-a] Existing branch '${branch}' is not aligned to ${base_ref} (${base_sha})." >&2
      echo "[worktree-phase-a] Refusing to repair it in-place during Phase A." >&2
      exit 23
    fi
  fi

  if [[ "${branch_exists}" -eq 0 ]]; then
    git -C "${canonical_root}" branch "${branch}" "${base_sha}" >/dev/null
  fi

  if command -v bd >/dev/null 2>&1; then
    (
      cd "${canonical_root}"
      bd worktree create "${target_path}" --branch "${branch}" >/dev/null
    )
  else
    git -C "${canonical_root}" worktree add "${target_path}" "${branch}" >/dev/null
  fi

  head_sha="$(git -C "${target_path}" rev-parse HEAD)"
  if [[ "${head_sha}" != "${base_sha}" ]]; then
    echo "[worktree-phase-a] Created worktree is not based on ${base_ref}." >&2
    echo "[worktree-phase-a] expected=${base_sha}" >&2
    echo "[worktree-phase-a] actual=${head_sha}" >&2
    echo "[worktree-phase-a] Stop. Do not refresh topology or repair the branch in-place." >&2
    exit 22
  fi

  render_success "${base_sha}" "${head_sha}"
}

main() {
  parse_args "$@"
  ensure_prerequisites

  case "${mode}" in
    create-from-base)
      create_from_base
      ;;
    *)
      die "Unsupported mode: ${mode}"
      ;;
  esac
}

main "$@"
