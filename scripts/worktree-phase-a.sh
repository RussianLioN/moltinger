#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/beads-resolve-db.sh
source "${SCRIPT_DIR}/beads-resolve-db.sh"

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
phase_a_export_path=""
phase_a_localize_seeded_from_export="false"

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
  command -v bd >/dev/null 2>&1 || die "bd is required"
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

phase_a_probe_localize_state() {
  local worktree_path="$1"
  local output=""
  local rc=0

  phase_a_localize_state=""
  phase_a_localize_action=""
  phase_a_localize_message=""
  phase_a_localize_notice=""
  phase_a_localize_runtime_repair_mode=""

  set +e
  output="$("${SCRIPT_DIR}/beads-worktree-localize.sh" --check --format env --path "${worktree_path}" 2>/dev/null)"
  rc=$?
  set -e

  unset schema worktree state action db_path message notice bootstrap_source runtime_repair_mode
  eval "${output}"

  phase_a_localize_state="${state:-}"
  phase_a_localize_action="${action:-}"
  phase_a_localize_message="${message:-}"
  phase_a_localize_notice="${notice:-}"
  phase_a_localize_runtime_repair_mode="${runtime_repair_mode:-}"
  return "${rc}"
}

phase_a_fail_runtime() {
  local state="${1:-unknown}"
  local message="${2:-Beads runtime could not be prepared in the new worktree.}"
  local notice="${3:-Run /usr/local/bin/bd doctor --json and ./scripts/beads-worktree-localize.sh --path . inside the target worktree before continuing.}"

  echo "[worktree-phase-a] ${message}" >&2
  if [[ -n "${notice}" ]]; then
    echo "[worktree-phase-a] ${notice}" >&2
  fi
  echo "[worktree-phase-a] state=${state}" >&2
  exit 23
}

phase_a_cleanup_export_artifact() {
  if [[ -n "${phase_a_export_path}" && -f "${phase_a_export_path}" ]]; then
    rm -f "${phase_a_export_path}"
  fi
}

phase_a_export_canonical_backlog() {
  local export_dir="${canonical_root}/.tmp/worktree-phase-a"

  mkdir -p "${export_dir}"
  phase_a_export_path="$(mktemp "${export_dir}/canonical-backlog.XXXXXX.jsonl")"

  if ! (
    cd "${canonical_root}"
    bd export -o "${phase_a_export_path}" >/dev/null 2>&1
  ); then
    phase_a_fail_runtime \
      "canonical_export_failed" \
      "Phase A could not export the live canonical Beads backlog before creating the new worktree." \
      "Run bd export from the canonical root and inspect canonical Beads runtime health there before retrying."
  fi
}

phase_a_prepare_beads_runtime() {
  local loop_count=0
  local bootstrap_attempted="false"
  local -a localize_args=("--path" "${target_path}")

  [[ -x "${SCRIPT_DIR}/beads-worktree-localize.sh" ]] || die "Missing beads-worktree-localize.sh; cannot verify worktree-local Beads ownership"
  if [[ -n "${phase_a_export_path}" ]]; then
    localize_args+=("--import-source" "${phase_a_export_path}")
  fi

  while [[ "${loop_count}" -lt 4 ]]; do
    loop_count=$((loop_count + 1))
    phase_a_probe_localize_state "${target_path}" || true

    case "${phase_a_localize_state}" in
      current|post_migration_runtime_only)
        return 0
        ;;
      migratable_legacy|bootstrap_required|partial_foundation)
        "${SCRIPT_DIR}/beads-worktree-localize.sh" "${localize_args[@]}" >/dev/null \
          || phase_a_fail_runtime "${phase_a_localize_state}" "${phase_a_localize_message}" "${phase_a_localize_notice}"
        if [[ -n "${phase_a_export_path}" ]]; then
          phase_a_localize_seeded_from_export="true"
        fi
        ;;
      runtime_bootstrap_required)
        if [[ "${bootstrap_attempted}" == "true" ]]; then
          phase_a_fail_runtime "${phase_a_localize_state}" "${phase_a_localize_message}" "${phase_a_localize_notice}"
        fi
        "${SCRIPT_DIR}/beads-worktree-localize.sh" "${localize_args[@]}" >/dev/null \
          || phase_a_fail_runtime "${phase_a_localize_state}" "${phase_a_localize_message}" "${phase_a_localize_notice}"
        if [[ -n "${phase_a_export_path}" ]]; then
          phase_a_localize_seeded_from_export="true"
        fi
        bootstrap_attempted="true"
        ;;
      *)
        phase_a_fail_runtime "${phase_a_localize_state:-unknown}" "${phase_a_localize_message}" "${phase_a_localize_notice}"
        ;;
    esac
  done

  phase_a_fail_runtime "${phase_a_localize_state:-unknown}" "Beads runtime did not converge to a healthy localized state during Phase A." "${phase_a_localize_notice}"
}

phase_a_import_canonical_backlog() {
  if [[ "${phase_a_localize_seeded_from_export}" == "true" ]]; then
    return 0
  fi

  [[ -n "${phase_a_export_path}" && -f "${phase_a_export_path}" ]] || phase_a_fail_runtime \
    "canonical_export_missing" \
    "Phase A lost the exported canonical Beads backlog before importing it into the new worktree." \
    "Retry the worktree create flow; the canonical backlog export artifact is required for a truthful handoff."

  (
    cd "${target_path}"
    bd import "${phase_a_export_path}" >/dev/null 2>&1
  ) || phase_a_fail_runtime \
    "canonical_import_failed" \
    "Phase A created the git worktree but could not import the live canonical Beads backlog into the new local runtime." \
    "Run /usr/local/bin/bd doctor --json and ./scripts/beads-worktree-localize.sh --path . inside the target worktree before retrying."
}

phase_a_wait_for_runtime_status() {
  local system_bd=""
  local attempts="${WORKTREE_PHASE_A_STATUS_RETRY_COUNT:-5}"
  local delay_seconds="${WORKTREE_PHASE_A_STATUS_RETRY_DELAY_SECONDS:-1}"
  local attempt=1
  local rc=0
  local output=""

  system_bd="$(beads_resolve_find_system_bd "${SCRIPT_DIR}/../bin/bd")" \
    || phase_a_fail_runtime "system_bd_missing" "Phase A could not locate the system bd binary for final runtime readiness checks."

  while [[ "${attempt}" -le "${attempts}" ]]; do
    set +e
    output="$(
      cd "${target_path}"
      "${system_bd}" status 2>&1
    )"
    rc=$?
    set -e

    if [[ "${rc}" -eq 0 ]]; then
      return 0
    fi

    if [[ "${attempt}" -lt "${attempts}" ]]; then
      sleep "${delay_seconds}"
    fi
    attempt=$((attempt + 1))
  done

  output="${output//$'\n'/ }"
  phase_a_fail_runtime \
    "runtime_not_ready" \
    "Phase A created the git worktree, but plain bd status never became ready in the new local runtime." \
    "Last status error: ${output}. Run /usr/local/bin/bd doctor --json and ./scripts/beads-worktree-localize.sh --path . inside the target worktree before retrying."
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

  phase_a_export_canonical_backlog

  if [[ "${branch_exists}" -eq 0 ]]; then
    git -C "${canonical_root}" branch "${branch}" "${base_sha}" >/dev/null
  fi

  git -C "${canonical_root}" worktree add "${target_path}" "${branch}" >/dev/null
  phase_a_prepare_beads_runtime
  phase_a_import_canonical_backlog
  phase_a_wait_for_runtime_status

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
  trap phase_a_cleanup_export_artifact EXIT
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
