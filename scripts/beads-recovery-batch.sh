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

sha256_string() {
  local value="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "${value}" | sha256sum | awk '{print $1}'
    return 0
  fi

  printf '%s' "${value}" | shasum -a 256 | awk '{print $1}'
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

source_issue_contract_json() {
  local issue_id="$1"
  local issue_jsonl="$2"
  local match_file=""
  local match_count=""
  local issue_digest=""
  local issue_state=""
  local issue_payload=""
  local issue_title=""
  local issue_priority=""
  local issue_status=""

  ensure_tmp_dir
  match_file="${tmp_dir}/source-issue-$(sanitize_path_component "${issue_id}").jsonl"
  jq -c --arg id "${issue_id}" 'select(.id == $id)' "${issue_jsonl}" > "${match_file}"
  match_count="$(wc -l < "${match_file}" | tr -d '[:space:]')"

  case "${match_count}" in
    0)
      issue_state="missing"
      ;;
    1)
      issue_state="present"
      issue_payload="$(cat "${match_file}")"
      issue_digest="$(sha256_string "${issue_payload}")"
      issue_title="$(printf '%s\n' "${issue_payload}" | jq -r '.title // ""')"
      issue_priority="$(printf '%s\n' "${issue_payload}" | jq -r 'if has("priority") then (.priority | tostring) else "" end')"
      issue_status="$(printf '%s\n' "${issue_payload}" | jq -r '.status // ""')"
      ;;
    *)
      issue_state="duplicate"
      ;;
  esac

  jq -nc \
    --arg state "${issue_state}" \
    --arg digest "${issue_digest}" \
    --arg title "${issue_title}" \
    --arg priority "${issue_priority}" \
    --arg status "${issue_status}" \
    '{
      state: $state,
      digest: ($digest | if . == "" then null else . end),
      title: ($title | if . == "" then null else . end),
      priority: ($priority | if . == "" then null else . end),
      status: ($status | if . == "" then null else . end)
    }'
}

candidate_validation_contract_json() {
  local issue_id="$1"
  local issue_jsonl="$2"
  local owner_branch="$3"
  local owner_worktree="$4"
  local beads_state="$5"
  local redirect_target="$6"
  local target_issue_present="$7"
  local source_contract=""

  source_contract="$(source_issue_contract_json "${issue_id}" "${issue_jsonl}")"
  jq -nc \
    --arg issue_id "${issue_id}" \
    --arg owner_branch "${owner_branch}" \
    --arg owner_worktree "${owner_worktree}" \
    --arg beads_state "${beads_state}" \
    --arg redirect_target "${redirect_target}" \
    --argjson target_issue_present "${target_issue_present}" \
    --argjson source_issue "${source_contract}" \
    '{
      issue_id: $issue_id,
      source_issue: $source_issue,
      owner_branch: $owner_branch,
      owner_worktree: $owner_worktree,
      beads_state: $beads_state,
      redirect_target: ($redirect_target | if . == "" then null else . end),
      target_issue_present: $target_issue_present
    }'
}

resolve_live_candidate_state_json() {
  local issue_id="$1"
  local issue_jsonl="$2"
  local owner_result=""
  local owner_branch=""
  local owner_reason=""
  local target_lines=""
  local target_count=""
  local source_contract=""
  local blocker=""
  local target_worktree=""
  local beads_state=""
  local redirect_target=""
  local target_issue_present="false"
  local target_issue_jsonl=""

  source_contract="$(source_issue_contract_json "${issue_id}" "${issue_jsonl}")"
  owner_result="$(ownership_branch_for_issue "${issue_id}")"

  case "${owner_result}" in
    __NONE__)
      jq -nc \
        --arg issue_id "${issue_id}" \
        --argjson source_issue "${source_contract}" \
        '{
          issue_id: $issue_id,
          source_issue: $source_issue,
          owner_state: "missing_owner_branch",
          owner_blocker: "missing_owner_branch",
          owner_branch: null,
          owner_worktree: null,
          beads_state: null,
          redirect_target: null,
          target_issue_present: false
        }'
      return 0
      ;;
    __BLOCKED__:* )
      blocker="${owner_result#__BLOCKED__:}"
      jq -nc \
        --arg issue_id "${issue_id}" \
        --arg blocker "${blocker}" \
        --argjson source_issue "${source_contract}" \
        '{
          issue_id: $issue_id,
          source_issue: $source_issue,
          owner_state: "blocked",
          owner_blocker: $blocker,
          owner_branch: null,
          owner_worktree: null,
          beads_state: null,
          redirect_target: null,
          target_issue_present: false
        }'
      return 0
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
  target_count="$(printf '%s\n' "${target_lines}" | sed '/^$/d' | wc -l | tr -d '[:space:]')"

  case "${target_count}" in
    0)
      if branch_snapshot_has_issue "${issue_id}" "${owner_branch}"; then
        jq -nc \
          --arg issue_id "${issue_id}" \
          --arg owner_branch "${owner_branch}" \
          --arg owner_reason "${owner_reason}" \
          --argjson source_issue "${source_contract}" \
          '{
            issue_id: $issue_id,
            source_issue: $source_issue,
            owner_state: "already_present_in_owner_branch",
            owner_blocker: "already_present_in_owner_branch",
            owner_branch: $owner_branch,
            ownership_reason: $owner_reason,
            owner_worktree: null,
            beads_state: null,
            redirect_target: null,
            target_issue_present: false
          }'
      else
        jq -nc \
          --arg issue_id "${issue_id}" \
          --arg owner_branch "${owner_branch}" \
          --arg owner_reason "${owner_reason}" \
          --argjson source_issue "${source_contract}" \
          '{
            issue_id: $issue_id,
            source_issue: $source_issue,
            owner_state: "missing_worktree",
            owner_blocker: "missing_worktree",
            owner_branch: $owner_branch,
            ownership_reason: $owner_reason,
            owner_worktree: null,
            beads_state: null,
            redirect_target: null,
            target_issue_present: false
          }'
      fi
      return 0
      ;;
    1) ;;
    *)
      jq -nc \
        --arg issue_id "${issue_id}" \
        --arg owner_branch "${owner_branch}" \
        --arg owner_reason "${owner_reason}" \
        --argjson source_issue "${source_contract}" \
        '{
          issue_id: $issue_id,
          source_issue: $source_issue,
          owner_state: "ambiguous_worktree",
          owner_blocker: "ambiguous_worktree",
          owner_branch: $owner_branch,
          ownership_reason: $owner_reason,
          owner_worktree: null,
          beads_state: null,
          redirect_target: null,
          target_issue_present: false
        }'
      return 0
      ;;
  esac

  target_worktree="${target_lines}"
  beads_state="$(jq -r --arg path "${target_worktree}" 'select(.path == $path) | .beads_state' "${worktrees_jsonl}")"
  redirect_target="$(jq -r --arg path "${target_worktree}" 'select(.path == $path) | .redirect_target' "${worktrees_jsonl}")"
  target_issue_jsonl="${target_worktree}/.beads/issues.jsonl"
  if target_has_issue "${issue_id}" "${target_issue_jsonl}"; then
    target_issue_present="true"
  fi

  jq -nc \
    --arg issue_id "${issue_id}" \
    --arg owner_branch "${owner_branch}" \
    --arg owner_reason "${owner_reason}" \
    --arg owner_worktree "${target_worktree}" \
    --arg beads_state "${beads_state}" \
    --arg redirect_target "${redirect_target}" \
    --argjson target_issue_present "${target_issue_present}" \
    --argjson source_issue "${source_contract}" \
    '{
      issue_id: $issue_id,
      source_issue: $source_issue,
      owner_state: "resolved",
      owner_blocker: null,
      owner_branch: $owner_branch,
      ownership_reason: $owner_reason,
      owner_worktree: $owner_worktree,
      beads_state: $beads_state,
      redirect_target: ($redirect_target | if . == "" then null else . end),
      target_issue_present: $target_issue_present
    }'
}

validation_reasons_json() {
  local candidate_json="$1"
  local current_json="$2"
  local planned_source_state=""
  local current_source_state=""
  local planned_source_digest=""
  local current_source_digest=""
  local planned_owner_branch=""
  local current_owner_branch=""
  local planned_owner_worktree=""
  local current_owner_worktree=""
  local planned_beads_state=""
  local current_beads_state=""
  local planned_redirect_target=""
  local current_redirect_target=""
  local current_owner_state=""
  local current_owner_blocker=""
  local reasons_json='[]'

  planned_source_state="$(printf '%s\n' "${candidate_json}" | jq -r '.validation_contract.source_issue.state // "missing"')"
  current_source_state="$(printf '%s\n' "${current_json}" | jq -r '.source_issue.state // "missing"')"
  planned_source_digest="$(printf '%s\n' "${candidate_json}" | jq -r '.validation_contract.source_issue.digest // ""')"
  current_source_digest="$(printf '%s\n' "${current_json}" | jq -r '.source_issue.digest // ""')"
  planned_owner_branch="$(printf '%s\n' "${candidate_json}" | jq -r '.validation_contract.owner_branch // ""')"
  current_owner_branch="$(printf '%s\n' "${current_json}" | jq -r '.owner_branch // ""')"
  planned_owner_worktree="$(printf '%s\n' "${candidate_json}" | jq -r '.validation_contract.owner_worktree // ""')"
  current_owner_worktree="$(printf '%s\n' "${current_json}" | jq -r '.owner_worktree // ""')"
  planned_beads_state="$(printf '%s\n' "${candidate_json}" | jq -r '.validation_contract.beads_state // ""')"
  current_beads_state="$(printf '%s\n' "${current_json}" | jq -r '.beads_state // ""')"
  planned_redirect_target="$(printf '%s\n' "${candidate_json}" | jq -r '.validation_contract.redirect_target // ""')"
  current_redirect_target="$(printf '%s\n' "${current_json}" | jq -r '.redirect_target // ""')"
  current_owner_state="$(printf '%s\n' "${current_json}" | jq -r '.owner_state // ""')"
  current_owner_blocker="$(printf '%s\n' "${current_json}" | jq -r '.owner_blocker // ""')"

  if [[ "${current_source_state}" != "present" ]]; then
    reasons_json="$(printf '%s\n' "${reasons_json}" | jq --arg reason "source_issue_${current_source_state}" '. + [$reason]')"
  elif [[ "${planned_source_state}" != "present" || "${current_source_digest}" != "${planned_source_digest}" ]]; then
    reasons_json="$(printf '%s\n' "${reasons_json}" | jq '. + ["source_issue_changed"]')"
  fi

  if [[ "${current_owner_state}" != "resolved" ]]; then
    reasons_json="$(printf '%s\n' "${reasons_json}" | jq --arg reason "${current_owner_blocker}" '. + [$reason]')"
  else
    if [[ "${current_owner_branch}" != "${planned_owner_branch}" ]]; then
      reasons_json="$(printf '%s\n' "${reasons_json}" | jq '. + ["owner_branch_changed"]')"
    fi
    if [[ "${current_owner_worktree}" != "${planned_owner_worktree}" ]]; then
      reasons_json="$(printf '%s\n' "${reasons_json}" | jq '. + ["owner_worktree_changed"]')"
    fi

    if [[ "${planned_beads_state}" == "redirected" && "${current_beads_state}" == "local" ]]; then
      :
    else
      if [[ "${current_beads_state}" != "${planned_beads_state}" ]]; then
        reasons_json="$(printf '%s\n' "${reasons_json}" | jq '. + ["beads_state_changed"]')"
      fi
      if [[ "${current_beads_state}" == "redirected" && "${planned_redirect_target}" != "${current_redirect_target}" ]]; then
        reasons_json="$(printf '%s\n' "${reasons_json}" | jq '. + ["redirect_target_changed"]')"
      fi
    fi
  fi

  printf '%s\n' "${reasons_json}"
}

validate_candidate_against_plan() {
  local candidate_json="$1"
  local plan_source_jsonl="$2"
  local issue_id=""
  local current_json=""
  local reasons_json=""
  local status="ok"
  local message=""
  local target_issue_present="false"

  issue_id="$(printf '%s\n' "${candidate_json}" | jq -r '.issue_id')"
  current_json="$(resolve_live_candidate_state_json "${issue_id}" "${plan_source_jsonl}")"
  reasons_json="$(validation_reasons_json "${candidate_json}" "${current_json}")"
  target_issue_present="$(printf '%s\n' "${current_json}" | jq -r '.target_issue_present')"

  if [[ "$(printf '%s\n' "${reasons_json}" | jq 'length')" != "0" ]]; then
    status="blocked"
    message="$(printf '%s\n' "${reasons_json}" | jq -r 'join(", ")')"
  elif [[ "${target_issue_present}" == "true" ]]; then
    status="already_present"
    message="issue already present in target worktree"
  else
    message="candidate contract still matches live state"
  fi

  jq -nc \
    --arg status "${status}" \
    --arg message "${message}" \
    --argjson reasons "${reasons_json}" \
    --argjson current "${current_json}" \
    '{
      status: $status,
      message: $message,
      reasons: $reasons,
      current: $current
    }'
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

branch_snapshot_has_issue() {
  local issue_id="$1"
  local branch_name="$2"
  local branch_issue_jsonl="${branch_name}:.beads/issues.jsonl"

  git cat-file -e "${branch_issue_jsonl}" 2>/dev/null || return 1
  git show "${branch_issue_jsonl}" 2>/dev/null | jq -e --arg id "${issue_id}" 'select(.id == $id)' >/dev/null 2>&1
}

append_candidate() {
  local candidate_json="$1"
  printf '%s\n' "${candidate_json}" >> "${candidates_jsonl}"
}

build_audit_candidates() {
  local issue_record=""
  local issue_id=""
  local title=""
  local issue_digest=""
  local owner_result=""
  local owner_branch=""
  local owner_reason=""
  local target_worktree=""
  local target_lines=""
  local blocker=""
  local requires_localization="false"
  local beads_state=""
  local redirect_target=""
  local source_state=""
  local confidence=""
  local candidate_json=""
  local target_issue_present="false"
  local validation_contract=""

  : > "${candidates_jsonl}"

  while IFS= read -r issue_record || [[ -n "${issue_record}" ]]; do
    [[ -n "${issue_record}" ]] || continue
    issue_id="$(printf '%s\n' "${issue_record}" | jq -r '.id')"
    title="$(printf '%s\n' "${issue_record}" | jq -r '.title')"
    issue_digest="$(sha256_string "${issue_record}")"
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
      if branch_snapshot_has_issue "${issue_id}" "${owner_branch}"; then
        candidate_json="$(
          jq -nc \
            --arg issue_id "${issue_id}" \
            --arg title "${title}" \
            --arg issue_digest "${issue_digest}" \
            --arg owner_branch "${owner_branch}" \
            --arg owner_reason "${owner_reason}" \
            '{
              issue_id: $issue_id,
              title: $title,
              issue_digest: $issue_digest,
              source_state: "already_present_in_owner_branch",
              owner_branch: $owner_branch,
              owner_worktree: null,
              ownership_reason: $owner_reason,
              confidence: "blocked",
              blockers: ["already_present_in_owner_branch"],
              requires_localization: false
            }'
        )"
      else
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
      fi
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
    redirect_target="$(jq -r --arg path "${target_worktree}" 'select(.path == $path) | .redirect_target' "${worktrees_jsonl}")"
    if [[ "${beads_state}" == "redirected" ]]; then
      requires_localization="true"
    else
      requires_localization="false"
    fi

    if target_has_issue "${issue_id}" "${target_worktree}/.beads/issues.jsonl"; then
      target_issue_present="true"
      source_state="already_present_in_target"
      confidence="blocked"
      validation_contract="$(
        candidate_validation_contract_json \
          "${issue_id}" \
          "${source_jsonl}" \
          "${owner_branch}" \
          "${target_worktree}" \
          "${beads_state}" \
          "${redirect_target}" \
          "${target_issue_present}"
      )"
      candidate_json="$(
        jq -nc \
          --arg issue_id "${issue_id}" \
          --arg title "${title}" \
          --arg issue_digest "${issue_digest}" \
          --arg source_state "${source_state}" \
          --arg owner_branch "${owner_branch}" \
          --arg owner_worktree "${target_worktree}" \
          --arg owner_reason "${owner_reason}" \
          --argjson requires_localization "${requires_localization}" \
          --argjson validation_contract "${validation_contract}" \
          '{
            issue_id: $issue_id,
            title: $title,
            issue_digest: $issue_digest,
            source_state: $source_state,
            owner_branch: $owner_branch,
            owner_worktree: $owner_worktree,
            ownership_reason: $owner_reason,
            confidence: "blocked",
            blockers: ["already_present"],
            requires_localization: $requires_localization,
            validation_contract: $validation_contract
          }'
      )"
      append_candidate "${candidate_json}"
      continue
    fi

    target_issue_present="false"
    source_state="root_only"
    validation_contract="$(
      candidate_validation_contract_json \
        "${issue_id}" \
        "${source_jsonl}" \
        "${owner_branch}" \
        "${target_worktree}" \
        "${beads_state}" \
        "${redirect_target}" \
        "${target_issue_present}"
    )"
    candidate_json="$(
      jq -nc \
        --arg issue_id "${issue_id}" \
        --arg title "${title}" \
        --arg issue_digest "${issue_digest}" \
        --arg source_state "${source_state}" \
        --arg owner_branch "${owner_branch}" \
        --arg owner_worktree "${target_worktree}" \
        --arg owner_reason "${owner_reason}" \
        --argjson requires_localization "${requires_localization}" \
        --argjson validation_contract "${validation_contract}" \
        '{
          issue_id: $issue_id,
          title: $title,
          issue_digest: $issue_digest,
          source_state: $source_state,
          owner_branch: $owner_branch,
          owner_worktree: $owner_worktree,
          ownership_reason: $owner_reason,
          confidence: "high",
          blockers: [],
          requires_localization: $requires_localization,
          validation_contract: $validation_contract
        }'
    )"
    append_candidate "${candidate_json}"
  done < <(jq -c '.' "${source_jsonl}")
}

write_audit_plan() {
  local topology_epoch=""
  local source_jsonl_digest=""
  local ownership_map_digest=""
  local total_root_issues=""
  local plan_json=""

  topology_epoch="$(topology_fingerprint)"
  source_jsonl_digest="$(sha256_file "${source_jsonl}")"
  if [[ -f "${ownership_map}" ]]; then
    ownership_map_digest="$(sha256_file "${ownership_map}")"
  else
    ownership_map_digest=""
  fi
  total_root_issues="$(wc -l < "${source_jsonl}" | tr -d '[:space:]')"
  mkdir -p "$(dirname "${output_path}")"

  plan_json="$(
    jq -n \
      --arg schema "beads-recovery-plan/v2" \
      --arg generated_at "$(now_utc)" \
      --arg canonical_root "${canonical_root}" \
      --arg source_jsonl "${source_jsonl}" \
      --arg topology_epoch "${topology_epoch}" \
      --arg topology_fingerprint "${topology_epoch}" \
      --arg source_jsonl_digest "${source_jsonl_digest}" \
      --arg ownership_map "$([[ -f "${ownership_map}" ]] && printf '%s' "${ownership_map}" || printf '')" \
      --arg ownership_map_digest "${ownership_map_digest}" \
      --argjson total_root_issues "${total_root_issues}" \
      --slurpfile candidates "${candidates_jsonl}" \
      '{
        schema: $schema,
        generated_at: $generated_at,
        canonical_root: $canonical_root,
        source_jsonl: $source_jsonl,
        source_jsonl_digest: $source_jsonl_digest,
        topology_epoch: $topology_epoch,
        topology_fingerprint: $topology_fingerprint,
        ownership_map: ($ownership_map | if . == "" then null else . end),
        ownership_map_digest: ($ownership_map_digest | if . == "" then null else . end),
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
  local current_topology_epoch=""
  local plan_topology_epoch=""
  local plan_schema=""
  local plan_source_jsonl=""
  local run_root=""
  local journal_path=""
  local actions_jsonl=""
  local backups_index=""
  local runtime_blocked_jsonl=""
  local planned_blocked_json=""
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
  local validation_json=""
  local validation_status=""
  local validation_message=""
  local current_beads_state=""
  local plan_requires_localization=""

  [[ -f "${plan_path}" ]] || die "Plan file not found: ${plan_path}"
  plan_schema="$(jq -r '.schema // "beads-recovery-plan/v1"' "${plan_path}")"
  current_topology_epoch="$(topology_fingerprint)"
  plan_topology_epoch="$(jq -r '.topology_epoch // .topology_fingerprint // ""' "${plan_path}")"

  if [[ "${plan_schema}" == "beads-recovery-plan/v1" && "${current_topology_epoch}" != "${plan_topology_epoch}" ]]; then
    echo "[beads-recovery-batch] Plan fingerprint does not match live topology" >&2
    echo "[beads-recovery-batch] expected=${plan_topology_epoch}" >&2
    echo "[beads-recovery-batch] actual=${current_topology_epoch}" >&2
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
  runtime_blocked_jsonl="${run_root}/runtime-blocked.jsonl"
  : > "${actions_jsonl}"
  : > "${backups_index}"
  : > "${runtime_blocked_jsonl}"
  cp "${plan_path}" "${run_root}/plan.json"
  started_at="$(now_utc)"

  while IFS= read -r candidate_row || [[ -n "${candidate_row}" ]]; do
    [[ -n "${candidate_row}" ]] || continue
    issue_id="$(printf '%s\n' "${candidate_row}" | jq -r '.issue_id')"
    target_worktree="$(printf '%s\n' "${candidate_row}" | jq -r '.owner_worktree')"
    plan_requires_localization="$(printf '%s\n' "${candidate_row}" | jq -r '.requires_localization')"
    localized="false"
    backup_path=""
    recover_output=""
    validation_json=""
    validation_status=""
    validation_message=""
    current_beads_state=""

    if [[ "${plan_schema}" == "beads-recovery-plan/v2" ]]; then
      collect_topology
      validation_json="$(validate_candidate_against_plan "${candidate_row}" "${plan_source_jsonl}")"
      validation_status="$(printf '%s\n' "${validation_json}" | jq -r '.status')"
      validation_message="$(printf '%s\n' "${validation_json}" | jq -r '.message')"
      current_beads_state="$(printf '%s\n' "${validation_json}" | jq -r '.current.beads_state // ""')"
      target_worktree="$(printf '%s\n' "${validation_json}" | jq -r '.current.owner_worktree // .owner_worktree // ""')"

      case "${validation_status}" in
        blocked)
          result_state="blocked_topology_drift"
          recover_output="Validation: ${validation_message}"
          any_failure=1
          jq -nc \
            --argjson candidate "${candidate_row}" \
            --argjson validation "${validation_json}" \
            '($candidate + {
              confidence: "blocked",
              blockers: ((($candidate.blockers // []) + $validation.reasons) | unique),
              apply_validation: $validation
            })' >> "${runtime_blocked_jsonl}"
          jq -nc \
            --arg issue_id "${issue_id}" \
            --arg target_worktree "${target_worktree}" \
            --argjson localized false \
            --arg backup_path "" \
            --arg result "${result_state}" \
            --arg details "${recover_output}" \
            --argjson validation "${validation_json}" \
            '{
              issue_id: $issue_id,
              target_worktree: ($target_worktree | if . == "" then null else . end),
              localized: $localized,
              backup_path: ($backup_path | if . == "" then null else . end),
              result: $result,
              details: $details,
              validation: $validation
            }' >> "${actions_jsonl}"
          continue
          ;;
        already_present)
          result_state="already_present"
          recover_output="Validation: ${validation_message}"
          jq -nc \
            --arg issue_id "${issue_id}" \
            --arg target_worktree "${target_worktree}" \
            --argjson localized false \
            --arg backup_path "" \
            --arg result "${result_state}" \
            --arg details "${recover_output}" \
            --argjson validation "${validation_json}" \
            '{
              issue_id: $issue_id,
              target_worktree: ($target_worktree | if . == "" then null else . end),
              localized: $localized,
              backup_path: ($backup_path | if . == "" then null else . end),
              result: $result,
              details: $details,
              validation: $validation
            }' >> "${actions_jsonl}"
          continue
          ;;
      esac
    else
      if [[ "${plan_requires_localization}" == "true" ]]; then
        current_beads_state="redirected"
      else
        current_beads_state="local"
      fi
    fi

    if [[ "${plan_requires_localization}" == "true" && "${current_beads_state}" == "redirected" ]]; then
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
      --argjson validation "$(
        if [[ -n "${validation_json}" ]]; then
          printf '%s\n' "${validation_json}"
        else
          printf 'null\n'
        fi
      )" \
      '{
        issue_id: $issue_id,
        target_worktree: $target_worktree,
        localized: $localized,
        backup_path: $backup_path,
        result: $result,
        details: $details,
        validation: $validation
      }' >> "${actions_jsonl}"
  done < <(jq -c '.candidates[] | select(.confidence == "high" and (.blockers | length == 0))' "${plan_path}")

  planned_blocked_json="$(jq '.candidates | map(select(.confidence != "high" or (.blockers | length > 0)))' "${plan_path}")"
  blocked_json="$(
    jq -n \
      --argjson planned "${planned_blocked_json}" \
      --slurpfile runtime "${runtime_blocked_jsonl}" \
      '$planned + $runtime'
  )"
  finished_at="$(now_utc)"

  jq -n \
    --arg schema "$([[ "${plan_schema}" == "beads-recovery-plan/v2" ]] && printf 'beads-recovery-journal/v2' || printf 'beads-recovery-journal/v1')" \
    --arg mode "apply" \
    --arg started_at "${started_at}" \
    --arg finished_at "${finished_at}" \
    --arg plan_path "${plan_path}" \
    --arg plan_schema "${plan_schema}" \
    --arg topology_epoch "${current_topology_epoch}" \
    --arg plan_topology_epoch "${plan_topology_epoch}" \
    --argjson blocked "${blocked_json}" \
    --argjson any_failure "${any_failure}" \
    --slurpfile actions "${actions_jsonl}" \
    '{
      schema: $schema,
      mode: $mode,
      started_at: $started_at,
      finished_at: $finished_at,
      plan_path: $plan_path,
      plan_schema: $plan_schema,
      topology_epoch: $topology_epoch,
      plan_topology_epoch: ($plan_topology_epoch | if . == "" then null else . end),
      topology_fingerprint: $topology_epoch,
      topology_drift_detected: (($plan_topology_epoch != "") and ($topology_epoch != $plan_topology_epoch)),
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
