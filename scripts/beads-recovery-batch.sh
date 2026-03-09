#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/beads-recovery-batch.sh audit --output <path> [--source-jsonl <path>] [--ownership-map <path>]
  scripts/beads-recovery-batch.sh apply --plan <path> [--journal-dir <path>]

Description:
  Audit leaked Beads issues in the canonical root tracker and safely recover only
  high-confidence items into localized owner worktrees.
EOF
}

die() {
  echo "[beads-recovery-batch] $*" >&2
  exit 2
}

mode=""
output_path=""
plan_path=""
journal_dir=""
source_jsonl=""
ownership_map=""
git_root=""
git_common_dir=""
canonical_root=""
tmp_dir=""
topology_porcelain_file=""
worktrees_jsonl=""
local_branches_file=""
candidates_jsonl=""

parse_args() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi

  mode="$1"
  shift

  case "${mode}" in
    audit|apply) ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown mode: ${mode}"
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        output_path="${2:-}"
        [[ -n "${output_path}" ]] || die "--output requires a value"
        shift 2
        ;;
      --plan)
        plan_path="${2:-}"
        [[ -n "${plan_path}" ]] || die "--plan requires a value"
        shift 2
        ;;
      --journal-dir)
        journal_dir="${2:-}"
        [[ -n "${journal_dir}" ]] || die "--journal-dir requires a value"
        shift 2
        ;;
      --source-jsonl)
        source_jsonl="${2:-}"
        [[ -n "${source_jsonl}" ]] || die "--source-jsonl requires a value"
        shift 2
        ;;
      --ownership-map)
        ownership_map="${2:-}"
        [[ -n "${ownership_map}" ]] || die "--ownership-map requires a value"
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

  if [[ "${mode}" == "audit" && -z "${output_path}" ]]; then
    die "audit requires --output"
  fi
  if [[ "${mode}" == "apply" && -z "${plan_path}" ]]; then
    die "apply requires --plan"
  fi
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

normalize_future_path() {
  local input_path="$1"
  local base_path="${2:-$PWD}"

  if [[ "${input_path}" == /* ]]; then
    printf '%s\n' "${input_path}"
    return 0
  fi

  printf '%s/%s\n' "${base_path%/}" "${input_path}"
}

sha256_file() {
  local target="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${target}" | awk '{print $1}'
    return 0
  fi

  shasum -a 256 "${target}" | awk '{print $1}'
}

ensure_context() {
  command -v git >/dev/null 2>&1 || die "git is required"
  command -v jq >/dev/null 2>&1 || die "jq is required"

  git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "${git_root}" ]] || die "Run this script inside the target repository"
  git_common_dir="$(git rev-parse --git-common-dir)"
  canonical_root="$(cd "${git_common_dir}" && cd .. && pwd -P)"

  if [[ -n "${output_path}" ]]; then
    output_path="$(normalize_future_path "${output_path}")"
  fi
  if [[ -n "${plan_path}" ]]; then
    plan_path="$(normalize_path "${plan_path}")"
  fi
  if [[ -n "${journal_dir}" ]]; then
    journal_dir="$(normalize_future_path "${journal_dir}")"
  fi
  if [[ -n "${source_jsonl}" ]]; then
    source_jsonl="$(normalize_path "${source_jsonl}")"
  else
    source_jsonl="${canonical_root}/.beads/issues.jsonl"
  fi
  if [[ -n "${ownership_map}" ]]; then
    ownership_map="$(normalize_path "${ownership_map}")"
  else
    ownership_map="${git_root}/docs/beads-recovery-ownership.json"
  fi

  [[ -f "${source_jsonl}" ]] || die "Source JSONL not found: ${source_jsonl}"
}

ensure_tmp_dir() {
  if [[ -n "${tmp_dir}" && -d "${tmp_dir}" ]]; then
    return 0
  fi

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/beads-recovery-batch.XXXXXX")"
  topology_porcelain_file="${tmp_dir}/worktrees.porcelain"
  worktrees_jsonl="${tmp_dir}/worktrees.jsonl"
  local_branches_file="${tmp_dir}/local-branches.txt"
  candidates_jsonl="${tmp_dir}/candidates.jsonl"
}

cleanup() {
  if [[ -n "${tmp_dir}" && -d "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}"
  fi
}

trap cleanup EXIT

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

collect_topology() {
  ensure_tmp_dir
  git worktree list --porcelain > "${topology_porcelain_file}"
  : > "${worktrees_jsonl}"
  git for-each-ref --format='%(refname:short)' refs/heads > "${local_branches_file}"

  local current_path=""
  local current_branch=""
  local line=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ -z "${line}" ]]; then
      if [[ -n "${current_path}" ]]; then
        append_worktree_json "${current_path}" "${current_branch}" >> "${worktrees_jsonl}"
      fi
      current_path=""
      current_branch=""
      continue
    fi

    case "${line}" in
      worktree\ *)
        current_path="${line#worktree }"
        current_branch=""
        ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        ;;
    esac
  done < "${topology_porcelain_file}"

  if [[ -n "${current_path}" ]]; then
    append_worktree_json "${current_path}" "${current_branch}" >> "${worktrees_jsonl}"
  fi
}

append_worktree_json() {
  local worktree_path="$1"
  local branch_name="$2"
  local beads_state="missing"
  local redirect_target=""

  if [[ -f "${worktree_path}/.beads/redirect" ]]; then
    beads_state="redirected"
    redirect_target="$(cat "${worktree_path}/.beads/redirect")"
  elif [[ -d "${worktree_path}/.beads" ]]; then
    beads_state="local"
  fi

  jq -nc \
    --arg path "${worktree_path}" \
    --arg branch "${branch_name}" \
    --arg beads_state "${beads_state}" \
    --arg redirect_target "${redirect_target}" \
    --arg canonical_root "${canonical_root}" \
    '{
      path: $path,
      branch: $branch,
      beads_state: $beads_state,
      redirect_target: $redirect_target,
      is_canonical_root: ($path == $canonical_root)
    }'
}

topology_fingerprint() {
  sha256_file "${topology_porcelain_file}"
}

ownership_branch_for_issue() {
  local issue_id="$1"
  local override_branch=""
  local branch_matches=""
  local branch_count=""

  if [[ -f "${ownership_map}" ]]; then
    override_branch="$(jq -r --arg id "${issue_id}" '
      (.entries // []) | map(select(.issue_id == $id)) |
      if length == 0 then "" elif length == 1 then .[0].branch else "__DUPLICATE__" end
    ' "${ownership_map}")"
    if [[ "${override_branch}" == "__DUPLICATE__" ]]; then
      printf '__BLOCKED__:%s\n' "duplicate_override"
      return 0
    fi
    if [[ -n "${override_branch}" ]]; then
      printf '__OWNER__:%s:%s\n' "${override_branch}" "ownership_override"
      return 0
    fi
  fi

  branch_matches="$(grep -F "${issue_id}" "${local_branches_file}" | grep -v '^main$' || true)"
  branch_count="$(printf '%s\n' "${branch_matches}" | sed '/^$/d' | wc -l | tr -d '[:space:]')"

  case "${branch_count}" in
    0)
      printf '__NONE__\n'
      ;;
    1)
      printf '__OWNER__:%s:%s\n' "${branch_matches}" "branch_contains_issue_id"
      ;;
    *)
      printf '__BLOCKED__:%s\n' "ambiguous_branch_owner"
      ;;
  esac
}

worktree_for_branch() {
  local branch_name="$1"
  jq -r --arg branch "${branch_name}" '
    select(.branch == $branch and .is_canonical_root == false) | .path
  ' "${worktrees_jsonl}"
}

target_has_issue() {
  local issue_id="$1"
  local target_jsonl="$2"

  [[ -f "${target_jsonl}" ]] || return 1
  jq -e --arg id "${issue_id}" 'select(.id == $id)' "${target_jsonl}" >/dev/null 2>&1
}

append_candidate() {
  local candidate_json="$1"
  printf '%s\n' "${candidate_json}" >> "${candidates_jsonl}"
}

build_audit_candidates() {
  local issue_record=""
  local issue_id=""
  local title=""
  local owner_result=""
  local owner_branch=""
  local owner_reason=""
  local target_worktree=""
  local target_lines=""
  local blocker=""
  local requires_localization="false"
  local beads_state=""
  local source_state=""
  local confidence=""
  local candidate_json=""

  : > "${candidates_jsonl}"

  while IFS= read -r issue_record || [[ -n "${issue_record}" ]]; do
    [[ -n "${issue_record}" ]] || continue
    issue_id="$(printf '%s\n' "${issue_record}" | jq -r '.id')"
    title="$(printf '%s\n' "${issue_record}" | jq -r '.title')"
    owner_result="$(ownership_branch_for_issue "${issue_id}")"

    case "${owner_result}" in
      __NONE__)
        continue
        ;;
      __BLOCKED__:* )
        blocker="${owner_result#__BLOCKED__:}"
        candidate_json="$(
          jq -nc \
            --arg issue_id "${issue_id}" \
            --arg title "${title}" \
            --arg blocker "${blocker}" \
            '{
              issue_id: $issue_id,
              title: $title,
              source_state: "root_only",
              owner_branch: null,
              owner_worktree: null,
              ownership_reason: null,
              confidence: "blocked",
              blockers: [$blocker],
              requires_localization: false
            }'
        )"
        append_candidate "${candidate_json}"
        continue
        ;;
      __OWNER__:* )
        owner_branch="${owner_result#__OWNER__:}"
        owner_reason="${owner_branch#*:}"
        owner_branch="${owner_branch%%:*}"
        ;;
      *)
        die "Unexpected owner resolution output: ${owner_result}"
        ;;
    esac

    target_lines="$(worktree_for_branch "${owner_branch}")"
    if [[ -z "${target_lines}" ]]; then
      candidate_json="$(
        jq -nc \
          --arg issue_id "${issue_id}" \
          --arg title "${title}" \
          --arg owner_branch "${owner_branch}" \
          --arg owner_reason "${owner_reason}" \
          '{
            issue_id: $issue_id,
            title: $title,
            source_state: "root_only",
            owner_branch: $owner_branch,
            owner_worktree: null,
            ownership_reason: $owner_reason,
            confidence: "blocked",
            blockers: ["missing_worktree"],
            requires_localization: false
          }'
      )"
      append_candidate "${candidate_json}"
      continue
    fi

    if [[ "$(printf '%s\n' "${target_lines}" | sed '/^$/d' | wc -l | tr -d '[:space:]')" != "1" ]]; then
      candidate_json="$(
        jq -nc \
          --arg issue_id "${issue_id}" \
          --arg title "${title}" \
          --arg owner_branch "${owner_branch}" \
          --arg owner_reason "${owner_reason}" \
          '{
            issue_id: $issue_id,
            title: $title,
            source_state: "root_only",
            owner_branch: $owner_branch,
            owner_worktree: null,
            ownership_reason: $owner_reason,
            confidence: "blocked",
            blockers: ["ambiguous_worktree"],
            requires_localization: false
          }'
      )"
      append_candidate "${candidate_json}"
      continue
    fi

    target_worktree="${target_lines}"
    beads_state="$(jq -r --arg path "${target_worktree}" 'select(.path == $path) | .beads_state' "${worktrees_jsonl}")"
    if [[ "${beads_state}" == "redirected" ]]; then
      requires_localization="true"
    else
      requires_localization="false"
    fi

    if target_has_issue "${issue_id}" "${target_worktree}/.beads/issues.jsonl"; then
      source_state="already_present_in_target"
      confidence="blocked"
      candidate_json="$(
        jq -nc \
          --arg issue_id "${issue_id}" \
          --arg title "${title}" \
          --arg source_state "${source_state}" \
          --arg owner_branch "${owner_branch}" \
          --arg owner_worktree "${target_worktree}" \
          --arg owner_reason "${owner_reason}" \
          --argjson requires_localization "${requires_localization}" \
          '{
            issue_id: $issue_id,
            title: $title,
            source_state: $source_state,
            owner_branch: $owner_branch,
            owner_worktree: $owner_worktree,
            ownership_reason: $owner_reason,
            confidence: "blocked",
            blockers: ["already_present"],
            requires_localization: $requires_localization
          }'
      )"
      append_candidate "${candidate_json}"
      continue
    fi

    source_state="root_only"
    candidate_json="$(
      jq -nc \
        --arg issue_id "${issue_id}" \
        --arg title "${title}" \
        --arg source_state "${source_state}" \
        --arg owner_branch "${owner_branch}" \
        --arg owner_worktree "${target_worktree}" \
        --arg owner_reason "${owner_reason}" \
        --argjson requires_localization "${requires_localization}" \
        '{
          issue_id: $issue_id,
          title: $title,
          source_state: $source_state,
          owner_branch: $owner_branch,
          owner_worktree: $owner_worktree,
          ownership_reason: $owner_reason,
          confidence: "high",
          blockers: [],
          requires_localization: $requires_localization
        }'
    )"
    append_candidate "${candidate_json}"
  done < <(jq -c '.' "${source_jsonl}")
}

write_audit_plan() {
  local fingerprint=""
  local total_root_issues=""
  local plan_json=""

  fingerprint="$(topology_fingerprint)"
  total_root_issues="$(wc -l < "${source_jsonl}" | tr -d '[:space:]')"
  mkdir -p "$(dirname "${output_path}")"

  plan_json="$(
    jq -n \
      --arg schema "beads-recovery-plan/v1" \
      --arg generated_at "$(now_utc)" \
      --arg canonical_root "${canonical_root}" \
      --arg source_jsonl "${source_jsonl}" \
      --arg topology_fingerprint "${fingerprint}" \
      --arg ownership_map "$([[ -f "${ownership_map}" ]] && printf '%s' "${ownership_map}" || printf '')" \
      --argjson total_root_issues "${total_root_issues}" \
      --slurpfile candidates "${candidates_jsonl}" \
      '{
        schema: $schema,
        generated_at: $generated_at,
        canonical_root: $canonical_root,
        source_jsonl: $source_jsonl,
        topology_fingerprint: $topology_fingerprint,
        ownership_map: ($ownership_map | if . == "" then null else . end),
        total_root_issues: $total_root_issues,
        safe_count: ($candidates | map(select(.confidence == "high" and (.blockers | length == 0))) | length),
        blocked_count: ($candidates | map(select(.confidence != "high" or (.blockers | length > 0))) | length),
        ignored_count: ($total_root_issues - ($candidates | length)),
        candidates: ($candidates | sort_by(.issue_id))
      }'
  )"
  printf '%s\n' "${plan_json}" > "${output_path}"

  printf 'Mode: audit\n'
  printf 'Plan: %s\n' "${output_path}"
  printf 'Safe Candidates: %s\n' "$(printf '%s\n' "${plan_json}" | jq -r '.safe_count')"
  printf 'Blocked Candidates: %s\n' "$(printf '%s\n' "${plan_json}" | jq -r '.blocked_count')"
  printf 'Ignored Root Issues: %s\n' "$(printf '%s\n' "${plan_json}" | jq -r '.ignored_count')"
}

sanitize_path_component() {
  printf '%s\n' "$1" | tr '/ ' '__' | tr -cd '[:alnum:]_.-'
}

ensure_backup_for_worktree() {
  local run_root="$1"
  local target_worktree="$2"
  local backups_index="$3"
  local target_key=""
  local backup_dir=""
  local backup_path=""

  target_key="$(sanitize_path_component "${target_worktree}")"
  backup_path="${run_root}/backups/${target_key}/issues.jsonl.bak"

  if grep -Fqx "${target_worktree}" "${backups_index}" 2>/dev/null; then
    printf '%s\n' "${backup_path}"
    return 0
  fi

  backup_dir="$(dirname "${backup_path}")"
  mkdir -p "${backup_dir}"
  cp "${target_worktree}/.beads/issues.jsonl" "${backup_path}"
  printf '%s\n' "${target_worktree}" >> "${backups_index}"
  printf '%s\n' "${backup_path}"
}

print_apply_summary() {
  local journal_path="$1"
  local journal_json=""

  journal_json="$(cat "${journal_path}")"
  printf 'Mode: apply\n'
  printf 'Journal: %s\n' "${journal_path}"
  printf 'Actions: %s\n' "$(printf '%s\n' "${journal_json}" | jq -r '.actions | length')"
  printf 'Failures: %s\n' "$(printf '%s\n' "${journal_json}" | jq -r '[.actions[] | select(.result == "failed")] | length')"
  printf 'Blocked Candidates: %s\n' "$(printf '%s\n' "${journal_json}" | jq -r '.blocked | length')"
  if [[ "$(printf '%s\n' "${journal_json}" | jq -r '.canonical_root_cleanup_allowed')" == "true" ]]; then
    printf 'Canonical Root Cleanup: may be considered separately\n'
  else
    printf 'Canonical Root Cleanup: still blocked\n'
  fi
}

run_apply() {
  local current_fingerprint=""
  local plan_fingerprint=""
  local plan_source_jsonl=""
  local run_root=""
  local journal_path=""
  local actions_jsonl=""
  local backups_index=""
  local blocked_json=""
  local any_failure=0
  local started_at=""
  local finished_at=""
  local candidate_row=""
  local issue_id=""
  local target_worktree=""
  local requires_localization=""
  local backup_path=""
  local recover_output=""
  local recover_rc=0
  local result_state=""
  local localized="false"

  [[ -f "${plan_path}" ]] || die "Plan file not found: ${plan_path}"
  current_fingerprint="$(topology_fingerprint)"
  plan_fingerprint="$(jq -r '.topology_fingerprint' "${plan_path}")"

  if [[ "${current_fingerprint}" != "${plan_fingerprint}" ]]; then
    echo "[beads-recovery-batch] Plan fingerprint does not match live topology" >&2
    echo "[beads-recovery-batch] expected=${plan_fingerprint}" >&2
    echo "[beads-recovery-batch] actual=${current_fingerprint}" >&2
    exit 3
  fi

  plan_source_jsonl="$(jq -r '.source_jsonl' "${plan_path}")"
  if [[ -n "${journal_dir}" ]]; then
    run_root="${journal_dir}/$(date -u +"%Y%m%dT%H%M%SZ")"
  else
    run_root="${git_root}/.tmp/current/beads-recovery-runs/$(date -u +"%Y%m%dT%H%M%SZ")"
  fi
  mkdir -p "${run_root}"
  journal_path="${run_root}/journal.json"
  actions_jsonl="${run_root}/actions.jsonl"
  backups_index="${run_root}/backups.index"
  : > "${actions_jsonl}"
  : > "${backups_index}"
  cp "${plan_path}" "${run_root}/plan.json"
  started_at="$(now_utc)"

  while IFS= read -r candidate_row || [[ -n "${candidate_row}" ]]; do
    [[ -n "${candidate_row}" ]] || continue
    issue_id="$(printf '%s\n' "${candidate_row}" | jq -r '.issue_id')"
    target_worktree="$(printf '%s\n' "${candidate_row}" | jq -r '.owner_worktree')"
    requires_localization="$(printf '%s\n' "${candidate_row}" | jq -r '.requires_localization')"
    localized="false"

    if [[ "${requires_localization}" == "true" ]]; then
      "${SCRIPT_DIR}/beads-worktree-localize.sh" --path "${target_worktree}" >/dev/null
      localized="true"
    fi

    backup_path="$(ensure_backup_for_worktree "${run_root}" "${target_worktree}" "${backups_index}")"

    set +e
    recover_output="$(
      "${SCRIPT_DIR}/beads-recover-issue.sh" \
        --issue "${issue_id}" \
        --source-jsonl "${plan_source_jsonl}" \
        --target-worktree "${target_worktree}" \
        --apply 2>&1
    )"
    recover_rc=$?
    set -e

    if [[ "${recover_rc}" -ne 0 ]]; then
      result_state="failed"
      any_failure=1
    else
      result_state="$(printf '%s\n' "${recover_output}" | awk -F': ' '$1 == "Result" {print $2}' | tail -1)"
      [[ -n "${result_state}" ]] || result_state="failed"
      if [[ "${result_state}" == "failed" ]]; then
        any_failure=1
      fi
    fi

    jq -nc \
      --arg issue_id "${issue_id}" \
      --arg target_worktree "${target_worktree}" \
      --argjson localized "${localized}" \
      --arg backup_path "${backup_path}" \
      --arg result "${result_state}" \
      --arg details "${recover_output}" \
      '{
        issue_id: $issue_id,
        target_worktree: $target_worktree,
        localized: $localized,
        backup_path: $backup_path,
        result: $result,
        details: $details
      }' >> "${actions_jsonl}"
  done < <(jq -c '.candidates[] | select(.confidence == "high" and (.blockers | length == 0))' "${plan_path}")

  blocked_json="$(jq '.candidates | map(select(.confidence != "high" or (.blockers | length > 0)))' "${plan_path}")"
  finished_at="$(now_utc)"

  jq -n \
    --arg schema "beads-recovery-journal/v1" \
    --arg mode "apply" \
    --arg started_at "${started_at}" \
    --arg finished_at "${finished_at}" \
    --arg plan_path "${plan_path}" \
    --arg topology_fingerprint "${current_fingerprint}" \
    --argjson blocked "${blocked_json}" \
    --argjson any_failure "${any_failure}" \
    --slurpfile actions "${actions_jsonl}" \
    '{
      schema: $schema,
      mode: $mode,
      started_at: $started_at,
      finished_at: $finished_at,
      plan_path: $plan_path,
      topology_fingerprint: $topology_fingerprint,
      canonical_root_cleanup_allowed: ((($blocked | length) == 0) and ($any_failure == 0)),
      actions: $actions,
      blocked: $blocked
    }' > "${journal_path}"

  print_apply_summary "${journal_path}"

  if [[ "${any_failure}" -ne 0 ]]; then
    exit 4
  fi
}

main() {
  parse_args "$@"
  ensure_context
  collect_topology

  case "${mode}" in
    audit)
      build_audit_candidates
      write_audit_plan
      ;;
    apply)
      run_apply
      ;;
  esac
}

main "$@"
