#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/beads-recover-issue.sh --issue <id> [--source-jsonl <path>] [--target-worktree <path>] [--apply]

Description:
  Safely recover one leaked Beads issue from a source JSONL snapshot into the
  localized tracker of the target worktree.

Default source JSONL:
  <canonical-root>/.beads/issues.jsonl
EOF
}

die() {
  echo "[beads-recover-issue] $*" >&2
  exit 2
}

issue_id=""
source_jsonl=""
target_worktree=""
apply_mode="false"
cleanup_tmp_dir=""
db_sync_state="unknown"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue)
        issue_id="${2:-}"
        [[ -n "${issue_id}" ]] || die "--issue requires a value"
        shift 2
        ;;
      --source-jsonl)
        source_jsonl="${2:-}"
        [[ -n "${source_jsonl}" ]] || die "--source-jsonl requires a value"
        shift 2
        ;;
      --target-worktree)
        target_worktree="${2:-}"
        [[ -n "${target_worktree}" ]] || die "--target-worktree requires a value"
        shift 2
        ;;
      --apply)
        apply_mode="true"
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

  [[ -n "${issue_id}" ]] || die "--issue is required"
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
    cd "$(dirname "${input_path}")"
    printf '%s/%s\n' "$(pwd -P)" "$(basename "${input_path}")"
  )
}

resolve_paths() {
  local git_common_dir=""
  local canonical_root=""

  if [[ -z "${target_worktree}" ]]; then
    target_worktree="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  else
    target_worktree="$(normalize_path "${target_worktree}")"
  fi
  [[ -n "${target_worktree}" ]] || die "Unable to resolve target worktree"
  git -C "${target_worktree}" rev-parse --show-toplevel >/dev/null 2>&1 || die "Not a git worktree: ${target_worktree}"

  if [[ -z "${source_jsonl}" ]]; then
    git_common_dir="$(git -C "${target_worktree}" rev-parse --git-common-dir)"
    canonical_root="$(cd "${git_common_dir}" && cd .. && pwd -P)"
    source_jsonl="${canonical_root}/.beads/issues.jsonl"
  else
    source_jsonl="$(normalize_path "${source_jsonl}")"
  fi
}

extract_issue_json() {
  local tmp_file="$1"
  local match_count=""

  [[ -f "${source_jsonl}" ]] || die "Source JSONL not found: ${source_jsonl}"
  command -v jq >/dev/null 2>&1 || die "jq is required"

  jq -c --arg id "${issue_id}" 'select(.id == $id)' "${source_jsonl}" > "${tmp_file}"
  match_count="$(wc -l < "${tmp_file}" | tr -d '[:space:]')"

  case "${match_count}" in
    1) ;;
    0) die "Issue '${issue_id}' was not found in ${source_jsonl}" ;;
    *) die "Issue '${issue_id}' matched ${match_count} records in ${source_jsonl}" ;;
  esac
}

target_jsonl_has_issue() {
  local target_jsonl="$1"

  [[ -f "${target_jsonl}" ]] || return 1
  jq -e --arg id "${issue_id}" 'select(.id == $id)' "${target_jsonl}" >/dev/null 2>&1
}

ensure_target_tracker() {
  local target_beads_dir="${target_worktree}/.beads"
  local target_redirect="${target_beads_dir}/redirect"
  local target_db="${target_beads_dir}/beads.db"
  local sync_output=""
  local sync_status=0

  [[ -d "${target_beads_dir}" ]] || die "Target worktree has no .beads directory: ${target_beads_dir}"
  [[ -f "${target_beads_dir}/config.yaml" ]] || die "Target worktree is missing ${target_beads_dir}/config.yaml"
  [[ -f "${target_beads_dir}/issues.jsonl" ]] || die "Target worktree is missing ${target_beads_dir}/issues.jsonl"
  if [[ -f "${target_redirect}" ]]; then
    die "Target worktree still has .beads/redirect. Run ./scripts/beads-worktree-localize.sh first."
  fi

  command -v bd >/dev/null 2>&1 || die "bd is required"

  if [[ ! -f "${target_db}" ]]; then
    (
      cd "${target_worktree}"
      BEADS_DB="${target_db}" bd --no-daemon list >/dev/null 2>&1
    )
  fi

  set +e
  sync_output="$(
    cd "${target_worktree}" && bd --no-daemon --db "${target_db}" sync --import-only 2>&1
  )"
  sync_status=$?
  set -e

  if [[ "${sync_status}" -eq 0 ]]; then
    db_sync_state="ok"
    return 0
  fi

  if [[ "${sync_output}" == *"prefix mismatch detected"* ]]; then
    db_sync_state="prefix_mismatch"
    return 0
  fi

  printf '%s\n' "${sync_output}" >&2
  die "Unable to align target DB with target JSONL"
}

render_summary() {
  local target_jsonl="$1"
  local target_db="$2"
  local source_state="present"
  local target_jsonl_state="missing"
  local target_db_state="missing"
  local result_state="$3"

  if target_jsonl_has_issue "${target_jsonl}"; then
    target_jsonl_state="present"
  fi

  if bd --no-daemon --db "${target_db}" show "${issue_id}" >/dev/null 2>&1; then
    target_db_state="present"
  fi

  printf 'Issue: %s\n' "${issue_id}"
  printf 'Mode: %s\n' "$([[ "${apply_mode}" == "true" ]] && printf 'apply' || printf 'audit')"
  printf 'Source JSONL: %s\n' "${source_jsonl}"
  printf 'Source Issue: %s\n' "${source_state}"
  printf 'Target Worktree: %s\n' "${target_worktree}"
  printf 'Target JSONL: %s\n' "${target_jsonl_state}"
  printf 'Target DB: %s\n' "${target_db_state}"
  printf 'DB Sync: %s\n' "${db_sync_state}"
  printf 'Result: %s\n' "${result_state}"
}

apply_recovery() {
  local issue_file="$1"
  local target_jsonl="$2"
  local target_db="$3"
  local tmp_jsonl=""

  tmp_jsonl="${cleanup_tmp_dir}/issues.jsonl"
  cp "${target_jsonl}" "${tmp_jsonl}"
  if [[ -s "${tmp_jsonl}" && -n "$(tail -c 1 "${tmp_jsonl}" 2>/dev/null || true)" ]]; then
    printf '\n' >> "${tmp_jsonl}"
  fi
  cat "${issue_file}" >> "${tmp_jsonl}"
  mv "${tmp_jsonl}" "${target_jsonl}"

  if [[ "${db_sync_state}" != "ok" ]]; then
    return 0
  fi

  (
    cd "${target_worktree}"
    bd --no-daemon --db "${target_db}" import -i "${issue_file}" --orphan-handling allow >/dev/null
    bd --no-daemon --db "${target_db}" sync >/dev/null
  )
}

main() {
  local issue_file=""
  local target_jsonl=""
  local target_db=""
  local result_state="ready_to_apply"

  parse_args "$@"
  resolve_paths

  target_jsonl="${target_worktree}/.beads/issues.jsonl"
  target_db="${target_worktree}/.beads/beads.db"
  ensure_target_tracker

  cleanup_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/beads-recover-issue.XXXXXX")"
  trap 'rm -rf "${cleanup_tmp_dir:-}"' EXIT
  issue_file="${cleanup_tmp_dir}/issue.jsonl"
  extract_issue_json "${issue_file}"

  if target_jsonl_has_issue "${target_jsonl}"; then
    result_state="already_present"
    render_summary "${target_jsonl}" "${target_db}" "${result_state}"
    return 0
  fi

  if [[ "${db_sync_state}" == "ok" ]]; then
    bd --no-daemon --db "${target_db}" import --dry-run -i "${issue_file}" --orphan-handling allow >/dev/null
  fi

  if [[ "${apply_mode}" == "true" ]]; then
    apply_recovery "${issue_file}" "${target_jsonl}" "${target_db}"
    if [[ "${db_sync_state}" == "ok" ]]; then
      result_state="imported"
    else
      result_state="imported_jsonl_only"
    fi
  fi

  render_summary "${target_jsonl}" "${target_db}" "${result_state}"
}

main "$@"
