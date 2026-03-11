#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/beads-resolve-db.sh
source "${REPO_ROOT}/scripts/beads-resolve-db.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/beads-worktree-localize.sh [--path <worktree>] [--format <human|env>] [--check]

Description:
  Localize Beads ownership for an existing git worktree by removing legacy
  redirect residue and materializing a worktree-local SQLite DB from the local
  JSONL/config foundation when that is safe to do.
EOF
}

die() {
  echo "[beads-worktree-localize] $*" >&2
  exit 2
}

target_path=""
output_format="human"
check_only="false"

report_state=""
report_action=""
report_worktree=""
report_db_path=""
report_message=""
report_notice=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)
        target_path="${2:-}"
        [[ -n "${target_path}" ]] || die "--path requires a value"
        shift 2
        ;;
      --format)
        output_format="${2:-}"
        [[ -n "${output_format}" ]] || die "--format requires a value"
        shift 2
        ;;
      --check)
        check_only="true"
        shift
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

  case "${output_format}" in
    human|env) ;;
    *)
      die "Unsupported output format: ${output_format}"
      ;;
  esac
}

ensure_worktree_context() {
  if [[ -z "${target_path}" ]]; then
    target_path="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  else
    target_path="$(beads_resolve_normalize_path "${target_path}")"
  fi

  [[ -n "${target_path}" ]] || die "Unable to resolve target worktree path"
  git -C "${target_path}" rev-parse --show-toplevel >/dev/null 2>&1 || die "Not a git worktree: ${target_path}"
  report_worktree="${target_path}"
}

classify_state() {
  local beads_dir="${target_path}/.beads"
  local config_path="${beads_dir}/config.yaml"
  local issues_path="${beads_dir}/issues.jsonl"
  local db_path="${beads_dir}/beads.db"
  local redirect_path="${beads_dir}/redirect"

  report_db_path="${db_path}"
  report_notice=""

  if [[ -f "${redirect_path}" ]]; then
    if [[ -f "${config_path}" && -f "${issues_path}" ]]; then
      report_state="migratable_legacy"
      report_action="localize_in_place"
      report_message="Legacy redirect metadata is present, but local foundation files are available for safe in-place localization."
      report_notice="Residual canonical-root cleanup remains a separate follow-up."
      return 0
    fi

    report_state="damaged_blocked"
    report_action="stop_and_report"
    report_message="Legacy redirect metadata is present, but local Beads foundation files are incomplete."
    report_notice="Do not fall back to the canonical root tracker."
    return 0
  fi

  if [[ -f "${config_path}" && -f "${issues_path}" && -f "${db_path}" ]]; then
    report_state="current"
    report_action="none"
    report_message="This worktree already has localized Beads ownership."
    return 0
  fi

  if [[ -f "${config_path}" && -f "${issues_path}" ]]; then
    report_state="partial_foundation"
    report_action="rebuild_local_foundation"
    report_message="Local Beads foundation exists, but the SQLite DB must be materialized in place."
    return 0
  fi

  report_state="damaged_blocked"
  report_action="stop_and_report"
  report_message="This worktree does not have enough local Beads foundation files to localize ownership safely."
}

materialize_local_db() {
  local system_bd="${BEADS_SYSTEM_BD:-}"

  if [[ -z "${system_bd}" ]]; then
    system_bd="$(beads_resolve_find_system_bd "${REPO_ROOT}/bin/bd")" || die "Could not locate the system bd binary"
  fi

  (
    cd "${target_path}"
    "${system_bd}" --db "${report_db_path}" info >/dev/null
  )
}

localize_state() {
  local redirect_path="${target_path}/.beads/redirect"

  case "${report_state}" in
    current)
      return 0
      ;;
    migratable_legacy)
      rm -f "${redirect_path}"
      materialize_local_db
      ;;
    partial_foundation)
      materialize_local_db
      ;;
    damaged_blocked)
      return 1
      ;;
    *)
      die "Unsupported localization state: ${report_state}"
      ;;
  esac

  classify_state
}

render_env() {
  printf 'schema=%q\n' "beads-localize/v1"
  printf 'worktree=%q\n' "${report_worktree}"
  printf 'state=%q\n' "${report_state}"
  printf 'action=%q\n' "${report_action}"
  printf 'db_path=%q\n' "${report_db_path}"
  printf 'message=%q\n' "${report_message}"
  printf 'notice=%q\n' "${report_notice}"
}

render_human() {
  printf 'Worktree: %s\n' "${report_worktree}"
  printf 'State: %s\n' "${report_state}"
  printf 'Action: %s\n' "${report_action}"
  printf 'DB Path: %s\n' "${report_db_path}"
  printf 'Message: %s\n' "${report_message}"
  if [[ -n "${report_notice}" ]]; then
    printf 'Notice: %s\n' "${report_notice}"
  fi
}

main() {
  parse_args "$@"
  ensure_worktree_context
  classify_state

  if [[ "${check_only}" != "true" ]]; then
    if [[ "${report_action}" == "stop_and_report" ]]; then
      render_human >&2
      exit 23
    fi
    localize_state
  fi

  if [[ "${output_format}" == "env" ]]; then
    render_env
  else
    render_human
  fi

  case "${report_action}" in
    stop_and_report)
      exit 23
      ;;
    *)
      exit 0
      ;;
  esac
}

main "$@"
