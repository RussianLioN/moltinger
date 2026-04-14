#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/beads-resolve-db.sh
source "${SCRIPT_DIR}/beads-resolve-db.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/worktree-ready.sh <mode> [options]

Modes:
  plan      Resolve one-shot worktree intent before mutating git state
  create    Prepare a new worktree flow for a new or derived branch
  attach    Prepare a worktree flow for an existing branch
  doctor    Diagnose readiness for an existing worktree
  finish    Prepare the safe ordinary finish contract for a target worktree
  cleanup   Execute the safe cleanup lifecycle for a target worktree
  handoff   Render or execute a handoff profile for a prepared worktree

Common Options:
  --branch <name>            Target git branch
  --slug <text>              Human task slug for branch/path derivation
  --issue <id>               Optional issue id for branch/path derivation
  --speckit                  Derive a numeric Speckit-compatible feature branch
  --path <path>              Explicit worktree path override
  --repo <path>              Repository root override
  --handoff <profile>        Handoff profile (manual|terminal|codex)
  --delete-branch            Delete local + remote branch after cleanup when merged proof exists
  --pending-summary <text>   Concrete deferred Phase B summary for handoff output
  --phase-b-seed-payload <text>
                            Structured deferred Phase B payload for rich handoff output
  --format <kind>            Output format (human|env)
  --existing <branch>        Existing branch hint for create flows
  -h, --help                 Show this help

Examples:
  scripts/worktree-ready.sh plan --slug remote-uat-hardening
  scripts/worktree-ready.sh plan --issue moltinger-dmi --slug telegram-webhook-rollout
  scripts/worktree-ready.sh create --branch 005-worktree-ready-flow
  scripts/worktree-ready.sh attach --branch codex/gitops-metrics-fix
  scripts/worktree-ready.sh doctor --path ../moltinger-0308-005-worktree-ready-flow
  scripts/worktree-ready.sh finish --branch feat/remote-uat-hardening
  scripts/worktree-ready.sh cleanup --branch feat/remote-uat-hardening --delete-branch
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
request_slug=""
issue_id=""
speckit_mode="false"
target_path=""
repo_root=""
handoff_profile="manual"
delete_branch_requested="false"
existing_branch=""
output_format="human"
pending_summary=""
phase_b_seed_payload=""
path_preview=""
resolved_repo_root=""
resolved_canonical_root=""
resolved_common_dir=""
canonical_repo_name=""
resolved_bd_command=""

report_worktree_path=""
report_path_preview=""
report_branch_name=""
report_issue_id=""
report_status="action_required"
report_env_state="unknown"
report_guard_state="unknown"
report_beads_state="missing"
report_beads_runtime_state="unknown"
report_beads_runtime_reason=""
report_handoff_mode="manual"
report_requested_handoff_mode="manual"
report_topology_state="unavailable"
report_phase="unknown"
report_boundary="none"
report_final_state="blocked_action_required"
report_approval_required="false"
report_launch_command=""
report_repair_command=""
report_pending_work=""
report_phase_b_seed_payload=""
report_worktree_action="unchanged"
report_issue_title=""
report_bootstrap_source_ref=""
report_close_action="skip"
report_close_command=""
report_local_branch_action="not_requested"
report_remote_branch_action="not_requested"
report_merge_check="not_requested"
report_default_branch_name=""
report_cleanup_reconcile_required="false"

declare -a report_next_steps=()
declare -a report_warnings=()
declare -a report_issue_artifacts=()
declare -a report_bootstrap_paths=()

discovered_worktree_name=""
discovered_worktree_path=""
discovered_branch_name=""
discovered_beads_state=""
discovered_beads_runtime_state=""
discovered_beads_runtime_probe_state="not_run"
discovered_beads_runtime_reason=""
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
guard_probe_status="not_run"
branch_resolution_state="not_required"
environment_probe_path=""
environment_state="unknown"
environment_probe_status="not_run"
handoff_support_state="unknown"
handoff_fallback_reason=""
handoff_launch_command=""
topology_registry_state="unavailable"
topology_registry_message=""
planning_decision="action_required"
planning_question=""
command_exit_code=0

declare -a planning_candidates=()
declare -a planning_next_steps=()
declare -a planning_warnings=()

parse_args() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      plan|create|attach|doctor|finish|cleanup|remove|handoff)
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
      --slug)
        request_slug="${2:-}"
        if [[ -z "${request_slug}" ]]; then
          die "--slug requires a value"
        fi
        shift 2
        ;;
      --issue)
        issue_id="${2:-}"
        if [[ -z "${issue_id}" ]]; then
          die "--issue requires a value"
        fi
        shift 2
        ;;
      --speckit)
        speckit_mode="true"
        shift
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
      --delete-branch)
        delete_branch_requested="true"
        shift
        ;;
      --pending-summary)
        pending_summary="${2:-}"
        if [[ -z "${pending_summary}" ]]; then
          die "--pending-summary requires a value"
        fi
        shift 2
        ;;
      --phase-b-seed-payload)
        phase_b_seed_payload="${2:-}"
        if [[ -z "${phase_b_seed_payload}" ]]; then
          die "--phase-b-seed-payload requires a value"
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
      --format)
        output_format="${2:-}"
        if [[ -z "${output_format}" ]]; then
          die "--format requires a value"
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

canonicalize_existing_directory_path() {
  local input_path="$1"
  local normalized_path=""

  normalized_path="$(normalize_path "${input_path}" "${resolved_repo_root}")"
  if [[ ! -d "${normalized_path}" ]]; then
    return 1
  fi

  (
    cd "${normalized_path}" >/dev/null 2>&1 || exit 1
    pwd -P
  )
}

path_identity_key() {
  local input_path="$1"
  local base_path="${2:-$PWD}"
  local normalized_path=""
  local canonical_path=""

  normalized_path="$(normalize_path "${input_path}" "${base_path}")"
  canonical_path="$(canonicalize_existing_directory_path "${normalized_path}" || true)"
  if [[ -n "${canonical_path}" ]]; then
    printf '%s\n' "${canonical_path}"
    return 0
  fi

  printf '%s\n' "${normalized_path}"
}

paths_refer_to_same_location() {
  local left_path="$1"
  local right_path="$2"
  local left_key=""
  local right_key=""

  left_key="$(path_identity_key "${left_path}" "/")"
  right_key="$(path_identity_key "${right_path}" "/")"
  [[ -n "${left_key}" && -n "${right_key}" && "${left_key}" == "${right_key}" ]]
}

url_encode_path_segment() {
  local raw_value="$1"
  local encoded=""
  local current_char=""
  local index=0

  for ((index = 0; index < ${#raw_value}; index++)); do
    current_char="${raw_value:index:1}"
    case "${current_char}" in
      [a-zA-Z0-9.~_-])
        encoded+="${current_char}"
        ;;
      *)
        printf -v encoded '%s%%%02X' "${encoded}" "'${current_char}"
        ;;
    esac
  done

  printf '%s\n' "${encoded}"
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

normalize_issue_key() {
  local raw_issue="$1"

  if [[ -z "${raw_issue}" || "${raw_issue}" == "n/a" ]]; then
    printf '\n'
    return 0
  fi

  printf '%s\n' "$(printf '%s' "${raw_issue}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
}

infer_issue_id_from_branch_name() {
  local branch_name="$1"
  local stripped_branch=""
  local issues_file=""
  local candidate_issue=""
  local normalized_issue=""
  local matched_issue=""
  local matched_issue_count=0
  local seen_matches=":"

  if [[ -z "${branch_name}" ]]; then
    printf '\n'
    return 0
  fi

  issues_file="${resolved_repo_root}/.beads/issues.jsonl"
  if [[ ! -f "${issues_file}" ]]; then
    printf '\n'
    return 0
  fi

  stripped_branch="$(strip_common_branch_prefix "${branch_name}")"
  if [[ -z "${stripped_branch}" ]]; then
    printf '\n'
    return 0
  fi

  while IFS= read -r candidate_issue; do
    normalized_issue="$(normalize_issue_key "${candidate_issue}")"
    if [[ -z "${normalized_issue}" ]]; then
      continue
    fi

    if [[ "${stripped_branch}" == "${normalized_issue}" || "${stripped_branch}" == "${normalized_issue}"-* ]]; then
      case "${seen_matches}" in
        *:"${candidate_issue}":*)
          continue
          ;;
      esac

      seen_matches="${seen_matches}${candidate_issue}:"
      matched_issue_count=$((matched_issue_count + 1))
      matched_issue="${candidate_issue}"
    fi
  done < <(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "${issues_file}")

  if [[ "${matched_issue_count}" -eq 1 ]]; then
    printf '%s\n' "${matched_issue}"
    return 0
  fi

  printf '\n'
}

resolve_report_issue_id() {
  if [[ -n "${issue_id}" ]]; then
    printf '%s\n' "${issue_id}"
    return 0
  fi

  if [[ -n "${branch}" ]]; then
    infer_issue_id_from_branch_name "${branch}"
    return 0
  fi

  printf '\n'
}

extract_issue_title_from_jsonl_line() {
  local issue_line="$1"

  if [[ -z "${issue_line}" ]]; then
    printf '\n'
    return 0
  fi

  printf '%s\n' "${issue_line}" \
    | sed -n 's/.*"title":"\([^"]*\)".*/\1/p' \
    | sed 's/\\"/"/g'
}

resolve_issue_jsonl_line() {
  local requested_issue="${1:-}"
  local issues_file=""

  if [[ -z "${requested_issue}" ]]; then
    printf '\n'
    return 0
  fi

  issues_file="${resolved_repo_root}/.beads/issues.jsonl"
  if [[ ! -f "${issues_file}" ]]; then
    printf '\n'
    return 0
  fi

  awk -v issue="${requested_issue}" 'index($0, "\"id\":\"" issue "\"") { print; exit }' "${issues_file}"
}

extract_issue_artifact_paths_from_jsonl_line() {
  local issue_line="$1"
  local candidate_path=""
  local normalized_path=""
  local seen_paths=""

  if [[ -z "${issue_line}" ]]; then
    return 0
  fi

  while IFS= read -r candidate_path; do
    if [[ -z "${candidate_path}" ]]; then
      continue
    fi

    normalized_path="${candidate_path#./}"
    if [[ -z "${normalized_path}" ]]; then
      continue
    fi

    if [[ ! -e "${resolved_repo_root}/${normalized_path}" ]]; then
      continue
    fi

    case ":${seen_paths}:" in
      *:"${normalized_path}":*)
        continue
        ;;
    esac

    seen_paths="${seen_paths}:${normalized_path}"
    printf '%s\n' "${normalized_path}"
  done < <(
    printf '%s\n' "${issue_line}" \
      | grep -oE '([A-Za-z0-9._-]+/)+[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+' \
      || true
  )
}

target_has_issue_record() {
  local issue_key="$1"
  local worktree_path="$2"
  local target_issues_file=""

  if [[ -z "${issue_key}" || -z "${worktree_path}" || ! -d "${worktree_path}" ]]; then
    return 1
  fi

  target_issues_file="${worktree_path}/.beads/issues.jsonl"
  if [[ ! -f "${target_issues_file}" ]]; then
    return 1
  fi

  grep -F "\"id\":\"${issue_key}\"" "${target_issues_file}" >/dev/null 2>&1
}

resolve_bootstrap_source_ref() {
  local upstream_ref=""
  local current_branch=""

  if upstream_ref="$(git -C "${resolved_repo_root}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
    if [[ -n "${upstream_ref}" && "${upstream_ref}" != "HEAD" ]]; then
      printf '%s\n' "${upstream_ref}"
      return 0
    fi
  fi

  current_branch="$(resolve_current_branch)"
  if [[ -n "${current_branch}" ]]; then
    printf '%s\n' "${current_branch}"
    return 0
  fi

  printf '\n'
}

add_bootstrap_path() {
  local artifact_path="$1"
  local existing_path=""

  if [[ -z "${artifact_path}" ]]; then
    return 0
  fi

  for existing_path in "${report_bootstrap_paths[@]}"; do
    if [[ "${existing_path}" == "${artifact_path}" ]]; then
      return 0
    fi
  done

  report_bootstrap_paths+=("${artifact_path}")
}

target_worktree_has_path() {
  local artifact_path="$1"

  if [[ -z "${artifact_path}" ]]; then
    return 1
  fi

  if ! report_worktree_path_exists; then
    return 1
  fi

  [[ -e "${report_worktree_path}/${artifact_path}" ]]
}

build_bootstrap_import_command() {
  local source_ref="${report_bootstrap_source_ref:-}"
  local artifact_path=""
  local command_text=""

  if [[ -z "${source_ref}" || "${#report_bootstrap_paths[@]}" -eq 0 ]]; then
    return 1
  fi

  command_text="git checkout $(shell_quote "${source_ref}") --"
  for artifact_path in "${report_bootstrap_paths[@]}"; do
    command_text+=" $(shell_quote "${artifact_path}")"
  done

  printf '%s\n' "${command_text}"
}

resolve_bd_command() {
  if [[ -n "${resolved_bd_command}" ]]; then
    printf '%s\n' "${resolved_bd_command}"
    return 0
  fi

  if [[ -n "${resolved_repo_root}" && -x "${resolved_repo_root}/bin/bd" ]]; then
    resolved_bd_command="${resolved_repo_root}/bin/bd"
    printf '%s\n' "${resolved_bd_command}"
    return 0
  fi

  if command -v bd >/dev/null 2>&1; then
    resolved_bd_command="$(command -v bd)"
    printf '%s\n' "${resolved_bd_command}"
    return 0
  fi

  return 1
}

resolve_bd_command_for_path() {
  local worktree_path="${1:-}"

  if [[ -n "${worktree_path}" && -x "${worktree_path}/bin/bd" ]]; then
    printf '%s\n' "${worktree_path}/bin/bd"
    return 0
  fi

  resolve_bd_command
}

resolve_system_bd_command_for_path() {
  local worktree_path="${1:-}"
  local bd_self_path=""

  if [[ -n "${worktree_path}" && -x "${worktree_path}/bin/bd" ]]; then
    bd_self_path="${worktree_path}/bin/bd"
  elif [[ -x "${resolved_repo_root}/bin/bd" ]]; then
    bd_self_path="${resolved_repo_root}/bin/bd"
  fi

  if [[ -n "${bd_self_path}" ]]; then
    beads_resolve_find_system_bd "${bd_self_path}" && return 0
  fi

  command -v bd >/dev/null 2>&1 || return 1
  command -v bd
}

run_bd_json_command_for_path() {
  local worktree_path="${1:-}"
  local bd_command=""

  shift || true

  if [[ -z "${worktree_path}" || ! -d "${worktree_path}" ]]; then
    return 1
  fi

  bd_command="$(resolve_bd_command_for_path "${worktree_path}")" || return 1
  (
    cd "${worktree_path}"
    "${bd_command}" "$@" 2>/dev/null
  )
}

path_has_live_beads_runtime() {
  local worktree_path="${1:-}"
  local beads_dir=""

  if [[ -z "${worktree_path}" || ! -d "${worktree_path}" ]]; then
    return 1
  fi

  beads_dir="${worktree_path}/.beads"
  beads_resolve_has_local_runtime "${beads_dir}"
}

WORKTREE_READY_LAST_BD_OUTPUT=""
WORKTREE_READY_LAST_BD_RC=0
WORKTREE_READY_LAST_BD_TIMED_OUT="false"

run_bd_probe_for_path() {
  local worktree_path="${1:-}"
  local capture_stderr="$2"
  shift 2

  local timeout_seconds="${WORKTREE_READY_BD_TIMEOUT_SECONDS:-8}"
  local command_path=""
  local stdout_file=""
  local stderr_file=""
  local timed_out_file=""
  local command_pid=""
  local watchdog_pid=""
  local rc=0
  local output=""

  if [[ -z "${worktree_path}" || ! -d "${worktree_path}" ]]; then
    return 1
  fi

  command_path="$(resolve_bd_command_for_path "${worktree_path}")" || return 1

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  timed_out_file="$(mktemp)"

  (
    cd "${worktree_path}"
    "${command_path}" "$@" >"${stdout_file}" 2>"${stderr_file}"
  ) &
  command_pid=$!

  (
    sleep "${timeout_seconds}"
    if kill -0 "${command_pid}" 2>/dev/null; then
      printf 'true\n' >"${timed_out_file}"
      kill -TERM "${command_pid}" 2>/dev/null || true
      sleep 1
      kill -KILL "${command_pid}" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!

  set +e
  wait "${command_pid}"
  rc=$?
  set -e

  kill "${watchdog_pid}" 2>/dev/null || true
  wait "${watchdog_pid}" 2>/dev/null || true

  WORKTREE_READY_LAST_BD_OUTPUT="$(cat "${stdout_file}")"
  if [[ "${capture_stderr}" == "true" ]]; then
    output="$(cat "${stderr_file}")"
    if [[ -n "${output}" ]]; then
      if [[ -n "${WORKTREE_READY_LAST_BD_OUTPUT}" ]]; then
        WORKTREE_READY_LAST_BD_OUTPUT+=$'\n'
      fi
      WORKTREE_READY_LAST_BD_OUTPUT+="${output}"
    fi
  fi

  WORKTREE_READY_LAST_BD_TIMED_OUT="false"
  WORKTREE_READY_LAST_BD_RC="${rc}"
  if [[ -s "${timed_out_file}" ]]; then
    WORKTREE_READY_LAST_BD_TIMED_OUT="true"
    WORKTREE_READY_LAST_BD_RC=124
  fi

  rm -f "${stdout_file}" "${stderr_file}" "${timed_out_file}"
  return 0
}

run_system_bd_probe_for_path() {
  local worktree_path="${1:-}"
  local capture_stderr="$2"
  shift 2

  local timeout_seconds="${WORKTREE_READY_BD_TIMEOUT_SECONDS:-8}"
  local command_path=""
  local stdout_file=""
  local stderr_file=""
  local timed_out_file=""
  local command_pid=""
  local watchdog_pid=""
  local rc=0
  local output=""

  if [[ -z "${worktree_path}" || ! -d "${worktree_path}" ]]; then
    return 1
  fi

  command_path="$(resolve_system_bd_command_for_path "${worktree_path}")" || return 1

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  timed_out_file="$(mktemp)"

  (
    cd "${worktree_path}"
    "${command_path}" "$@" >"${stdout_file}" 2>"${stderr_file}"
  ) &
  command_pid=$!

  (
    sleep "${timeout_seconds}"
    if kill -0 "${command_pid}" 2>/dev/null; then
      printf 'true\n' >"${timed_out_file}"
      kill -TERM "${command_pid}" 2>/dev/null || true
      sleep 1
      kill -KILL "${command_pid}" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!

  set +e
  wait "${command_pid}"
  rc=$?
  set -e

  kill "${watchdog_pid}" 2>/dev/null || true
  wait "${watchdog_pid}" 2>/dev/null || true

  WORKTREE_READY_LAST_BD_OUTPUT="$(cat "${stdout_file}")"
  if [[ "${capture_stderr}" == "true" ]]; then
    output="$(cat "${stderr_file}")"
    if [[ -n "${output}" ]]; then
      if [[ -n "${WORKTREE_READY_LAST_BD_OUTPUT}" ]]; then
        WORKTREE_READY_LAST_BD_OUTPUT+=$'\n'
      fi
      WORKTREE_READY_LAST_BD_OUTPUT+="${output}"
    fi
  fi

  WORKTREE_READY_LAST_BD_TIMED_OUT="false"
  WORKTREE_READY_LAST_BD_RC="${rc}"
  if [[ -s "${timed_out_file}" ]]; then
    WORKTREE_READY_LAST_BD_TIMED_OUT="true"
    WORKTREE_READY_LAST_BD_RC=124
  fi

  rm -f "${stdout_file}" "${stderr_file}" "${timed_out_file}"
  return 0
}

iter_known_issue_ids() {
  local issues_file=""
  local live_issue_ids=""

  if command -v jq >/dev/null 2>&1; then
    live_issue_ids="$(run_bd_json_command_for_path "${resolved_repo_root}" list --all --json 2>/dev/null || true)"
    if [[ -n "${live_issue_ids}" ]]; then
      printf '%s\n' "${live_issue_ids}" | jq -r '.[]? | .id // empty'
    fi
  fi

  issues_file="${resolved_repo_root}/.beads/issues.jsonl"
  if [[ -f "${issues_file}" ]]; then
    sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "${issues_file}"
  fi
}

resolve_issue_live_object_json_for_path() {
  local worktree_path="${1:-}"
  local requested_issue="${2:-}"
  local issue_json=""

  if [[ -z "${worktree_path}" || -z "${requested_issue}" ]]; then
    return 1
  fi

  command -v jq >/dev/null 2>&1 || return 1

  issue_json="$(run_bd_json_command_for_path "${worktree_path}" show "${requested_issue}" --json 2>/dev/null || true)"
  [[ -n "${issue_json}" ]] || return 1

  printf '%s\n' "${issue_json}" \
    | jq -ce 'if type == "array" then .[0] else . end | select(type == "object")'
}

resolve_issue_context_json() {
  local requested_issue="${1:-}"
  local issue_object=""
  local issue_line=""

  if [[ -z "${requested_issue}" ]]; then
    return 1
  fi

  issue_object="$(resolve_issue_live_object_json_for_path "${resolved_repo_root}" "${requested_issue}" 2>/dev/null || true)"
  if [[ -n "${issue_object}" ]]; then
    printf '%s\n' "${issue_object}" \
      | jq -c '{
          source: "live",
          id: (.id // ""),
          title: (.title // ""),
          text: ([.title, .description, .body, .details] | map(select(type == "string" and length > 0)) | join("\n"))
        }'
    return 0
  fi

  issue_line="$(resolve_issue_jsonl_line "${requested_issue}")"
  if [[ -n "${issue_line}" ]]; then
    jq -cn \
      --arg requested_issue "${requested_issue}" \
      --arg issue_title "$(extract_issue_title_from_jsonl_line "${issue_line}")" \
      --arg issue_text "${issue_line}" \
      '{
        source: "jsonl",
        id: $requested_issue,
        title: $issue_title,
        text: $issue_text
      }'
    return 0
  fi

  return 1
}

build_plain_bd_bootstrap_command_for_path() {
  local worktree_path="${1:-}"

  if [[ -z "${worktree_path}" || "${worktree_path}" == "n/a" ]]; then
    return 1
  fi

  printf 'export PATH=%s:$PATH\n' "$(shell_quote "${worktree_path}/bin")"
}

build_phase_a_create_command_for_target() {
  local target_branch="${1:-${branch:-}}"
  local worktree_path="${2:-${target_path:-}}"
  local canonical_root=""

  if [[ -z "${target_branch}" || -z "${worktree_path}" || "${worktree_path}" == "n/a" ]]; then
    return 1
  fi

  canonical_root="$(beads_resolve_canonical_root "${resolved_repo_root}" 2>/dev/null || printf '%s\n' "${resolved_repo_root}")"
  printf 'scripts/worktree-phase-a.sh create-from-base --canonical-root %s --base-ref %s --branch %s --path %s\n' \
    "$(shell_quote "${canonical_root}")" \
    "$(shell_quote "main")" \
    "$(shell_quote "${target_branch}")" \
    "$(shell_quote "${worktree_path}")"
}

build_finish_commit_message() {
  local finish_branch="${report_branch_name:-${branch:-worktree}}"

  if [[ -n "${report_issue_id:-}" && "${report_issue_id}" != "n/a" ]]; then
    printf '%s: finish %s\n' "${report_issue_id}" "${finish_branch}"
    return 0
  fi

  printf 'finish %s\n' "${finish_branch}"
}

build_finish_commit_command() {
  local commit_message=""

  commit_message="$(build_finish_commit_message)"
  printf 'if [ -n "$(git status --short)" ]; then git add -A && git commit -m %s; fi\n' "$(shell_quote "${commit_message}")"
}

build_finish_close_command() {
  local resolved_issue="${report_issue_id:-}"
  local quoted_issue=""
  local quoted_reason=""

  if [[ -z "${resolved_issue}" || "${resolved_issue}" == "n/a" ]]; then
    return 1
  fi

  quoted_issue="$(shell_quote "${resolved_issue}")"
  quoted_reason="$(shell_quote "Done")"
  printf 'bd close %s --reason %s || bd close --no-db %s --reason %s\n' "${quoted_issue}" "${quoted_reason}" "${quoted_issue}" "${quoted_reason}"
}

build_finish_review_command() {
  local worktree_path="${1:-}"

  if [[ -z "${worktree_path}" || "${worktree_path}" == "n/a" ]]; then
    return 1
  fi

  if [[ -f "${worktree_path}/.beads/cutover-mode.json" ]]; then
    printf './scripts/beads-dolt-rollout.sh verify --worktree .\n'
    return 0
  fi

  if [[ -f "${worktree_path}/.beads/pilot-mode.json" ]]; then
    printf './scripts/beads-dolt-pilot.sh review\n'
    return 0
  fi

  printf 'bd status\n'
}

resolve_default_branch_name() {
  local default_branch=""
  local repo_json=""

  default_branch="$(git -C "${resolved_repo_root}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  default_branch="${default_branch#origin/}"
  if [[ -n "${default_branch}" ]]; then
    printf '%s\n' "${default_branch}"
    return 0
  fi

  if origin_uses_github && gh_available_and_authenticated && command -v jq >/dev/null 2>&1; then
    repo_json="$(gh_run_in_repo repo view --json defaultBranchRef 2>/dev/null || true)"
    default_branch="$(printf '%s\n' "${repo_json}" | jq -r '.defaultBranchRef.name // empty' 2>/dev/null || true)"
    if [[ -n "${default_branch}" ]]; then
      printf '%s\n' "${default_branch}"
      return 0
    fi
  fi

  printf 'main\n'
}

origin_uses_github() {
  local origin_url=""

  if [[ "${WORKTREE_READY_ASSUME_GITHUB_ORIGIN:-0}" == "1" ]]; then
    return 0
  fi

  origin_url="$(git -C "${resolved_repo_root}" remote get-url origin 2>/dev/null || true)"
  [[ "${origin_url}" == *github.com* ]]
}

gh_available_and_authenticated() {
  command -v gh >/dev/null 2>&1 || return 1
  gh auth status -h github.com >/dev/null 2>&1
}

gh_run_in_repo() {
  if [[ -z "${resolved_repo_root:-}" ]]; then
    return 1
  fi

  (
    cd "${resolved_repo_root}" &&
      gh "$@"
  )
}

github_repo_name_with_owner() {
  local repo_json=""
  local repo_name_with_owner=""

  if ! origin_uses_github || ! gh_available_and_authenticated || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  repo_json="$(gh_run_in_repo repo view --json nameWithOwner 2>/dev/null || true)"
  repo_name_with_owner="$(printf '%s\n' "${repo_json}" | jq -r '.nameWithOwner // empty' 2>/dev/null || true)"
  if [[ -z "${repo_name_with_owner}" ]]; then
    return 1
  fi

  printf '%s\n' "${repo_name_with_owner}"
}

github_delete_ref_command() {
  local cleanup_branch="$1"
  local repo_name_with_owner=""
  local encoded_branch=""

  repo_name_with_owner="$(github_repo_name_with_owner || true)"
  if [[ -z "${repo_name_with_owner}" ]]; then
    return 1
  fi

  encoded_branch="$(url_encode_path_segment "${cleanup_branch}")"
  printf 'gh api -X DELETE %s\n' "$(shell_quote "repos/${repo_name_with_owner}/git/refs/heads/${encoded_branch}")"
}

delete_remote_branch_via_github_api() {
  local cleanup_branch="$1"
  local repo_name_with_owner=""
  local encoded_branch=""

  repo_name_with_owner="$(github_repo_name_with_owner || true)"
  if [[ -z "${repo_name_with_owner}" ]]; then
    return 1
  fi

  encoded_branch="$(url_encode_path_segment "${cleanup_branch}")"
  gh_run_in_repo api -X DELETE "repos/${repo_name_with_owner}/git/refs/heads/${encoded_branch}"
  git -C "${resolved_repo_root}" update-ref -d "refs/remotes/origin/${cleanup_branch}" >/dev/null 2>&1 || true
}

github_branch_head_sha() {
  local cleanup_branch="$1"
  local repo_name_with_owner=""
  local encoded_branch=""
  local ref_json=""
  local ref_sha=""

  repo_name_with_owner="$(github_repo_name_with_owner || true)"
  if [[ -z "${repo_name_with_owner}" ]]; then
    return 1
  fi

  encoded_branch="$(url_encode_path_segment "${cleanup_branch}")"
  ref_json="$(gh_run_in_repo api "repos/${repo_name_with_owner}/git/ref/heads/${encoded_branch}" 2>/dev/null || true)"
  ref_sha="$(printf '%s\n' "${ref_json}" | jq -r '.object.sha // empty' 2>/dev/null || true)"
  if [[ -z "${ref_sha}" ]]; then
    return 1
  fi

  printf '%s\n' "${ref_sha}"
}

resolve_ref_sha() {
  local ref_name="$1"

  git -C "${resolved_repo_root}" rev-parse --verify "${ref_name}^{commit}" 2>/dev/null || true
}

ref_is_ancestor_of_remote_default() {
  local candidate_ref="$1"
  local default_branch_name="$2"

  git -C "${resolved_repo_root}" merge-base --is-ancestor "${candidate_ref}" "refs/remotes/origin/${default_branch_name}" 2>/dev/null
}

refresh_cleanup_remote_refs() {
  git -C "${resolved_repo_root}" fetch --prune --no-tags origin >/dev/null 2>&1
}

cleanup_output_indicates_false_unpushed_guard() {
  local output="$1"

  [[ "${output}" == *"safety check failed"* && "${output}" == *"unpushed commit"* ]]
}

worktree_has_clean_status() {
  local worktree_path="$1"
  local status_output=""

  status_output="$(git -C "${worktree_path}" status --short --untracked-files=normal 2>/dev/null || true)"
  [[ -z "${status_output}" ]]
}

git_worktree_record_for_path() {
  local search_path="$1"
  local search_identity_key=""
  local line=""
  local current_path=""
  local current_branch=""
  local current_prunable=""
  local current_locked=""
  local current_identity_key=""

  search_identity_key="$(path_identity_key "${search_path}" "${resolved_repo_root}")"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      worktree\ *)
        current_path="$(normalize_path "${line#worktree }" "/")"
        current_identity_key="$(path_identity_key "${current_path}" "/")"
        current_branch=""
        current_prunable=""
        current_locked=""
        ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        ;;
      prunable*)
        current_prunable="${line#prunable }"
        [[ "${current_prunable}" == "${line}" ]] && current_prunable="true"
        ;;
      locked*)
        current_locked="${line#locked }"
        [[ "${current_locked}" == "${line}" ]] && current_locked="true"
        ;;
      "")
        if [[ -n "${current_path}" && -n "${current_identity_key}" && "${current_identity_key}" == "${search_identity_key}" ]]; then
          printf '%s\t%s\t%s\t%s\n' "${current_path}" "${current_branch}" "${current_prunable}" "${current_locked}"
          return 0
        fi
        current_path=""
        current_identity_key=""
        current_branch=""
        current_prunable=""
        current_locked=""
        ;;
    esac
  done < <(git -C "${resolved_repo_root}" worktree list --porcelain)

  if [[ -n "${current_path}" && -n "${current_identity_key}" && "${current_identity_key}" == "${search_identity_key}" ]]; then
    printf '%s\t%s\t%s\t%s\n' "${current_path}" "${current_branch}" "${current_prunable}" "${current_locked}"
    return 0
  fi

  return 1
}

worktree_path_is_prunable() {
  local worktree_path="$1"
  local record=""
  local prunable_reason=""

  record="$(git_worktree_record_for_path "${worktree_path}" || true)"
  if [[ -z "${record}" ]]; then
    return 1
  fi

  IFS=$'\t' read -r _ _ prunable_reason _ <<< "${record}"
  [[ -n "${prunable_reason}" ]]
}

wait_for_worktree_removal() {
  local worktree_path="$1"
  local attempt=0

  while [[ "${attempt}" -lt 5 ]]; do
    if [[ ! -d "${worktree_path}" ]] && ! git_worktree_record_for_path "${worktree_path}" >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  return 1
}

resolve_cleanup_merge_proof() {
  local cleanup_branch="$1"
  local default_branch_name="$2"
  local allow_local_stale_proof="${3:-false}"
  local local_sha=""
  local remote_sha=""
  local expected_sha=""
  local remote_refresh_ok="true"
  local repo_json=""
  local pr_json=""
  local repo_delete_branch_on_merge=""
  local match_count=""
  local merged_url=""

  report_merge_check="not_requested"
  report_default_branch_name="${default_branch_name}"

  if ! refresh_cleanup_remote_refs; then
    remote_refresh_ok="false"
  fi

  if [[ "${remote_refresh_ok}" == "true" ]] && remote_branch_exists "${cleanup_branch}"; then
    remote_sha="$(resolve_ref_sha "refs/remotes/origin/${cleanup_branch}")"
    if [[ -n "${remote_sha}" ]] && ref_is_ancestor_of_remote_default "refs/remotes/origin/${cleanup_branch}" "${default_branch_name}"; then
      report_merge_check="git_ancestor_remote"
      return 0
    fi
  fi

  if [[ "${remote_refresh_ok}" == "true" ]] && local_branch_exists "${cleanup_branch}"; then
    local_sha="$(resolve_ref_sha "refs/heads/${cleanup_branch}")"
    if [[ -n "${local_sha}" && -z "${remote_sha}" ]] && ref_is_ancestor_of_remote_default "refs/heads/${cleanup_branch}" "${default_branch_name}"; then
      report_merge_check="git_ancestor_local"
      return 0
    fi
  fi

  if [[ "${remote_refresh_ok}" != "true" ]] && origin_uses_github && gh_available_and_authenticated && command -v jq >/dev/null 2>&1; then
    remote_sha="$(github_branch_head_sha "${cleanup_branch}" || true)"
  fi

  if [[ -z "${local_sha}" ]] && local_branch_exists "${cleanup_branch}"; then
    local_sha="$(resolve_ref_sha "refs/heads/${cleanup_branch}")"
  fi

  if [[ "${remote_refresh_ok}" != "true" && "${allow_local_stale_proof}" == "true" && -n "${local_sha}" ]] \
    && ref_is_ancestor_of_remote_default "refs/heads/${cleanup_branch}" "${default_branch_name}"; then
    report_merge_check="git_ancestor_local_stale"
    add_warning "Remote ref refresh failed; using local merged ancestry only to authorize worktree removal fallback for '${cleanup_branch}'. Branch deletion remains blocked until remote proof is restored."
    return 0
  fi

  expected_sha="${remote_sha:-${local_sha}}"
  if [[ -z "${expected_sha}" ]]; then
    report_merge_check="missing_branch_tip"
    return 1
  fi

  if ! origin_uses_github; then
    if [[ "${remote_refresh_ok}" != "true" ]]; then
      report_merge_check="remote_refresh_failed"
      return 1
    fi
    report_merge_check="not_merged"
    return 1
  fi

  if ! gh_available_and_authenticated || ! command -v jq >/dev/null 2>&1; then
    if [[ "${remote_refresh_ok}" != "true" ]]; then
      report_merge_check="remote_refresh_failed"
      return 1
    fi
    report_merge_check="github_unavailable"
    return 1
  fi

  repo_json="$(gh_run_in_repo repo view --json deleteBranchOnMerge,defaultBranchRef 2>/dev/null || true)"
  repo_delete_branch_on_merge="$(printf '%s\n' "${repo_json}" | jq -r '.deleteBranchOnMerge // empty' 2>/dev/null || true)"
  if [[ -z "${report_default_branch_name}" ]]; then
    report_default_branch_name="$(printf '%s\n' "${repo_json}" | jq -r '.defaultBranchRef.name // empty' 2>/dev/null || true)"
  fi
  if [[ -n "${repo_delete_branch_on_merge}" && "${repo_delete_branch_on_merge}" == "false" ]]; then
    add_warning "GitHub auto-delete for merged head branches is disabled for this repository; cleanup must explicitly remove remote branches when merge proof exists."
  fi

  pr_json="$(gh_run_in_repo pr list --state merged --head "${cleanup_branch}" --json number,state,mergedAt,headRefName,headRefOid,baseRefName,isCrossRepository,url,title 2>/dev/null || true)"
  match_count="$(
    printf '%s\n' "${pr_json}" | jq -r \
      --arg branch "${cleanup_branch}" \
      --arg base "${default_branch_name}" \
      --arg head_sha "${expected_sha}" \
      '[ .[] | select(.state == "MERGED" and .mergedAt != null and .headRefName == $branch and .baseRefName == $base and (.isCrossRepository | not) and .headRefOid == $head_sha) ] | length' \
      2>/dev/null || printf '0'
  )"

  if [[ "${match_count}" == "1" ]]; then
    merged_url="$(printf '%s\n' "${pr_json}" | jq -r \
      --arg branch "${cleanup_branch}" \
      --arg base "${default_branch_name}" \
      --arg head_sha "${expected_sha}" \
      '.[] | select(.state == "MERGED" and .mergedAt != null and .headRefName == $branch and .baseRefName == $base and (.isCrossRepository | not) and .headRefOid == $head_sha) | .url' \
      2>/dev/null || true)"
    report_merge_check="github_pr_merged"
    if [[ -n "${merged_url}" ]]; then
      add_warning "GitHub merged PR fallback confirmed safe branch deletion via ${merged_url}."
    fi
    return 0
  fi

  if [[ "${match_count}" =~ ^[0-9]+$ ]] && [[ "${match_count}" -gt 1 ]]; then
    report_merge_check="github_pr_ambiguous"
  else
    report_merge_check="not_merged"
  fi
  return 1
}

resolve_cleanup_target_branch_name() {
  if [[ -n "${report_worktree_path}" && -n "${discovered_worktree_path}" && "${report_worktree_path}" == "${discovered_worktree_path}" && -n "${discovered_branch_name}" ]]; then
    printf '%s\n' "${discovered_branch_name}"
    return 0
  fi

  if [[ -n "${report_branch_name}" && "${report_branch_name}" != "n/a" ]]; then
    printf '%s\n' "${report_branch_name}"
    return 0
  fi

  if [[ -n "${branch}" ]]; then
    printf '%s\n' "${branch}"
    return 0
  fi

  return 1
}

cleanup_target_arguments_conflict() {
  local target_branch=""

  if [[ -z "${branch}" || -z "${target_path}" ]]; then
    return 1
  fi

  if [[ -z "${discovered_worktree_path}" ]] || ! paths_refer_to_same_location "${discovered_worktree_path}" "${target_path}"; then
    return 0
  fi

  target_branch="$(resolve_cleanup_target_branch_name || true)"
  [[ -z "${target_branch}" || "${target_branch}" != "${branch}" ]]
}

discover_issue_context() {
  local resolved_issue=""
  local issues_file=""
  local issue_line=""
  local artifact_path=""
  local artifact_report=""
  local has_research_artifact=0

  resolved_issue="${report_issue_id:-}"
  if [[ -z "${resolved_issue}" || "${resolved_issue}" == "n/a" ]]; then
    return 0
  fi

  issues_file="${resolved_repo_root}/.beads/issues.jsonl"
  if [[ ! -f "${issues_file}" ]]; then
    return 0
  fi

  issue_line="$(resolve_issue_jsonl_line "${resolved_issue}")"
  if [[ -z "${issue_line}" ]]; then
    return 0
  fi

  report_issue_title="$(extract_issue_title_from_jsonl_line "${issue_line}")"
  report_bootstrap_source_ref="$(resolve_bootstrap_source_ref)"

  if report_worktree_path_exists && ! target_has_issue_record "${resolved_issue}" "${report_worktree_path}"; then
    add_warning "Issue '${resolved_issue}' is not present in target worktree Beads state; rely on the handoff context instead of local bd show."
    add_bootstrap_path ".beads/issues.jsonl"
  fi

  while IFS= read -r artifact_path; do
    if [[ -z "${artifact_path}" ]]; then
      continue
    fi

    if report_worktree_path_exists && [[ -e "${report_worktree_path}/${artifact_path}" ]]; then
      artifact_report="${artifact_path} [present in target]"
    else
      artifact_report="${artifact_path} [source only; missing in target]"
      add_warning "Issue artifact '${artifact_path}' is not present in the target worktree."
      add_bootstrap_path "${artifact_path}"
    fi

    if [[ "${artifact_path}" == docs/research/* ]]; then
      has_research_artifact=1
    fi

    report_issue_artifacts+=("${artifact_report}")
  done < <(extract_issue_artifact_paths_from_jsonl_line "${issue_line}")

  if [[ "${has_research_artifact}" -eq 1 && -e "${resolved_repo_root}/docs/research/README.md" ]] && ! target_worktree_has_path "docs/research/README.md"; then
    add_bootstrap_path "docs/research/README.md"
  fi
}

speckit_branching_enabled() {
  local requested_issue="${issue_id:-}"
  local issue_line=""

  if [[ "${speckit_mode}" == "true" ]]; then
    return 0
  fi

  if [[ -z "${requested_issue}" ]]; then
    return 1
  fi

  issue_line="$(resolve_issue_jsonl_line "${requested_issue}")"
  if [[ -z "${issue_line}" ]]; then
    return 1
  fi

  [[ "${issue_line}" =~ [Ss]peckit|/speckit|spec\.md|plan\.md|tasks\.md|specs/ ]]
}

issue_requests_speckit() {
  speckit_branching_enabled
}

normalize_slug_token() {
  local raw_slug="$1"

  if [[ -z "${raw_slug}" ]]; then
    printf 'task\n'
    return 0
  fi

  printf '%s\n' "$(printf '%s' "${raw_slug}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
}

strip_common_branch_prefix() {
  local candidate="$1"

  candidate="${candidate#origin/}"
  candidate="${candidate#refs/heads/}"
  candidate="${candidate#refs/remotes/}"
  candidate="${candidate#${canonical_repo_name}-}"

  for prefix in feat/ feat- fix/ fix- hotfix/ hotfix- bugfix/ bugfix- chore/ chore- codex/ codex- uat/ uat- test/ test-; do
    candidate="${candidate#${prefix}}"
  done

  printf '%s\n' "${candidate}"
}

issue_short_key() {
  local normalized_issue="$1"
  local repo_prefix="${canonical_repo_name}-"

  if [[ -z "${normalized_issue}" ]]; then
    printf '\n'
    return 0
  fi

  printf '%s\n' "${normalized_issue#${repo_prefix}}"
}

derive_effective_slug() {
  local normalized_slug=""
  local normalized_issue=""
  local short_issue=""

  normalized_slug="$(normalize_slug_token "${request_slug}")"
  normalized_issue="$(normalize_issue_key "${issue_id}")"

  if [[ -n "${normalized_issue}" ]]; then
    short_issue="$(issue_short_key "${normalized_issue}")"
    normalized_slug="${normalized_slug#${normalized_issue}-}"
    normalized_slug="${normalized_slug#${short_issue}-}"
    normalized_slug="${normalized_slug#${canonical_repo_name}-}"
  fi

  if [[ -z "${normalized_slug}" ]]; then
    normalized_slug="task"
  fi

  printf '%s\n' "${normalized_slug}"
}

extract_numeric_feature_prefix() {
  local candidate="$1"

  if [[ "${candidate}" =~ ^([0-9]{3})- ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  printf '\n'
}

iter_spec_feature_dirs() {
  local specs_dir="${resolved_repo_root}/specs"
  local dir=""

  if [[ ! -d "${specs_dir}" ]]; then
    return 0
  fi

  for dir in "${specs_dir}"/*; do
    [[ -d "${dir}" ]] || continue
    printf '%s\n' "$(basename "${dir}")"
  done
}

find_existing_speckit_branch_for_slug() {
  local feature_slug="$1"
  local candidate=""
  local normalized=""
  local candidate_number=""
  local best_candidate=""
  local best_number=0

  if [[ -z "${feature_slug}" ]]; then
    printf '\n'
    return 0
  fi

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    normalized="${candidate#origin/}"
    normalized="${normalized#refs/heads/}"
    normalized="${normalized#refs/remotes/}"
    if [[ "${normalized}" =~ ^([0-9]{3})-${feature_slug}$ ]]; then
      candidate_number="$((10#${BASH_REMATCH[1]}))"
      if [[ -z "${best_candidate}" || "${candidate_number}" -gt "${best_number}" ]]; then
        best_candidate="${normalized}"
        best_number="${candidate_number}"
      fi
    fi
  done < <(
    {
      iter_local_branches
      iter_remote_branches
      iter_spec_feature_dirs
    } | awk 'NF && !seen[$0]++'
  )

  printf '%s\n' "${best_candidate}"
}

highest_speckit_feature_number() {
  local candidate=""
  local normalized=""
  local candidate_number=""
  local highest=0

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    normalized="${candidate#origin/}"
    normalized="${normalized#refs/heads/}"
    normalized="${normalized#refs/remotes/}"
    candidate_number="$(extract_numeric_feature_prefix "${normalized}")"
    if [[ -n "${candidate_number}" ]]; then
      candidate_number="$((10#${candidate_number}))"
      if [[ "${candidate_number}" -gt "${highest}" ]]; then
        highest="${candidate_number}"
      fi
    fi
  done < <(
    {
      iter_local_branches
      iter_remote_branches
      iter_spec_feature_dirs
    } | awk 'NF && !seen[$0]++'
  )

  printf '%s\n' "${highest}"
}

derive_speckit_branch_from_request() {
  local effective_slug=""
  local exact_branch=""
  local next_number=0

  effective_slug="$(derive_effective_slug)"
  exact_branch="$(find_existing_speckit_branch_for_slug "${effective_slug}")"
  if [[ -n "${exact_branch}" ]]; then
    printf '%s\n' "${exact_branch}"
    return 0
  fi

  next_number="$(highest_speckit_feature_number)"
  next_number=$((next_number + 1))
  printf '%03d-%s\n' "${next_number}" "${effective_slug}"
}

derive_branch_from_request() {
  local normalized_issue=""

  if [[ -n "${branch}" ]]; then
    printf '%s\n' "${branch}"
    return 0
  fi

  if issue_requests_speckit; then
    derive_speckit_branch_from_request
    return 0
  fi

  normalized_issue="$(normalize_issue_key "${issue_id}")"

  if [[ -n "${normalized_issue}" ]]; then
    printf 'feat/%s-%s\n' "${normalized_issue}" "$(derive_effective_slug)"
    return 0
  fi

  printf 'feat/%s\n' "$(derive_effective_slug)"
}

format_request_worktree_dirname() {
  local normalized_issue=""
  local short_issue=""
  local effective_slug=""

  effective_slug="$(derive_effective_slug)"
  normalized_issue="$(normalize_issue_key "${issue_id}")"

  if [[ -n "${normalized_issue}" ]]; then
    short_issue="$(issue_short_key "${normalized_issue}")"
    printf '%s-%s-%s\n' "${canonical_repo_name}" "${short_issue}" "${effective_slug}"
    return 0
  fi

  printf '%s-%s\n' "${canonical_repo_name}" "${effective_slug}"
}

derive_worktree_suffix_from_branch() {
  local branch_name="$1"
  local stripped_branch=""
  local normalized_suffix=""

  stripped_branch="$(strip_common_branch_prefix "${branch_name}")"
  if [[ -z "${stripped_branch}" ]]; then
    printf '%s\n' "$(sanitize_branch_name "${branch_name}")"
    return 0
  fi

  normalized_suffix="$(normalize_slug_token "${stripped_branch}")"
  if [[ -z "${normalized_suffix}" || "${normalized_suffix}" == "task" ]]; then
    printf '%s\n' "$(sanitize_branch_name "${branch_name}")"
    return 0
  fi

  printf '%s\n' "${normalized_suffix}"
}

format_worktree_dirname() {
  local branch_name="$1"

  printf '%s-%s\n' "${canonical_repo_name}" "$(derive_worktree_suffix_from_branch "${branch_name}")"
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

derive_request_worktree_path() {
  path_preview="../$(format_request_worktree_dirname)"
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
  resolved_canonical_root="$(beads_resolve_canonical_root "${resolved_repo_root}" 2>/dev/null || printf '%s\n' "${resolved_repo_root}")"
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
  discovered_beads_probe_state="not_run"
  discovered_beads_runtime_state=""
  discovered_beads_runtime_probe_state="not_run"
  discovered_beads_runtime_reason=""
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
  guard_probe_status="not_run"
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
  environment_probe_status="not_run"
  environment_state="unknown"
}

reset_handoff_selection() {
  handoff_support_state="unknown"
  handoff_fallback_reason=""
  handoff_launch_command=""
}

map_bd_beads_state() {
  local raw_state="$1"

  case "${raw_state}" in
    local)
      printf 'local\n'
      ;;
    shared)
      printf 'shared\n'
      ;;
    redirect)
      printf 'redirected\n'
      ;;
    none|"")
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
  local worktree_path=""
  local worktree_branch=""

  while IFS=$'\t' read -r worktree_path worktree_branch; do
    if paths_refer_to_same_location "${worktree_path}" "${search_path}"; then
      printf '%s\t%s\n' "${worktree_path}" "${worktree_branch}"
      return 0
    fi
  done < <(iter_git_worktrees)

  return 1
}

iter_local_branches() {
  git -C "${resolved_repo_root}" for-each-ref --format='%(refname:short)' refs/heads
}

iter_remote_branches() {
  git -C "${resolved_repo_root}" for-each-ref --format='%(refname:short)' refs/remotes/origin \
    | grep -v '^origin/HEAD$' || true
}

local_branch_exists() {
  local candidate_branch="$1"

  git -C "${resolved_repo_root}" show-ref --verify --quiet "refs/heads/${candidate_branch}"
}

remote_branch_exists() {
  local candidate_branch="$1"

  git -C "${resolved_repo_root}" show-ref --verify --quiet "refs/remotes/origin/${candidate_branch}"
}

count_shared_tokens() {
  local left="$1"
  local right="$2"
  local token=""
  local count=0
  local -a left_tokens=()
  local -a right_tokens=()
  declare -A seen_right=()

  IFS='-' read -r -a left_tokens <<< "${left}"
  IFS='-' read -r -a right_tokens <<< "${right}"

  for token in "${right_tokens[@]}"; do
    if [[ ${#token} -ge 3 ]]; then
      seen_right["${token}"]=1
    fi
  done

  for token in "${left_tokens[@]}"; do
    if [[ ${#token} -ge 3 && -n "${seen_right[${token}]:-}" ]]; then
      count=$((count + 1))
    fi
  done

  printf '%s\n' "${count}"
}

candidate_similarity_key() {
  local raw_name="$1"
  local key=""

  key="$(sanitize_branch_name "$(strip_common_branch_prefix "${raw_name}")")"
  key="${key#${canonical_repo_name}-}"

  printf '%s\n' "${key}"
}

candidate_matches_slug() {
  local candidate_name="$1"
  local slug_key="$2"
  local candidate_key=""
  local shared_tokens=0

  candidate_key="$(candidate_similarity_key "${candidate_name}")"

  if [[ -z "${candidate_key}" || -z "${slug_key}" ]]; then
    return 1
  fi

  if [[ "${candidate_key}" == "${slug_key}" || "${candidate_key}" == *"${slug_key}"* || "${slug_key}" == *"${candidate_key}"* ]]; then
    return 0
  fi

  shared_tokens="$(count_shared_tokens "${candidate_key}" "${slug_key}")"
  [[ "${shared_tokens}" -ge 2 ]]
}

reset_plan_state() {
  planning_decision="action_required"
  planning_question=""
  planning_candidates=()
  planning_next_steps=()
  planning_warnings=()
}

add_plan_candidate() {
  local candidate_type="$1"
  local candidate_name="$2"
  local candidate_path="${3:--}"
  local candidate_reason="$4"
  local candidate_record=""

  candidate_record="${candidate_type}"$'\t'"${candidate_name}"$'\t'"${candidate_path}"$'\t'"${candidate_reason}"

  if printf '%s\n' "${planning_candidates[@]:-}" | grep -Fqx "${candidate_record}" 2>/dev/null; then
    return 0
  fi

  planning_candidates+=("${candidate_record}")
}

discover_topology_registry_state() {
  local output=""
  local exit_code=0
  local script_path="${resolved_repo_root}/scripts/git-topology-registry.sh"

  topology_registry_state="unavailable"
  topology_registry_message=""

  if [[ ! -x "${script_path}" ]]; then
    return 0
  fi

  set +e
  output="$(
    cd "${resolved_repo_root}" && "${script_path}" check 2>&1
  )"
  exit_code=$?
  set -e

  topology_registry_message="$(printf '%s' "${output}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

  if [[ "${output}" == *"status=ok"* ]]; then
    topology_registry_state="ok"
  elif [[ "${output}" == *"status=stale"* ]]; then
    topology_registry_state="stale"
  elif [[ "${exit_code}" -eq 0 ]]; then
    topology_registry_state="ok"
  fi
}

discover_similar_targets() {
  local slug_key="$1"
  local branch_name="$2"
  local candidate_branch=""
  local candidate_path=""
  local attached_branch=""

  if [[ -z "${slug_key}" ]]; then
    return 0
  fi

  while IFS=$'\t' read -r candidate_path attached_branch; do
    if [[ -z "${candidate_path}" ]]; then
      continue
    fi

    if [[ -n "${attached_branch}" && "${attached_branch}" == "${branch_name}" ]]; then
      add_plan_candidate "worktree" "${attached_branch}" "${candidate_path}" "exact-attached-branch"
      continue
    fi

    if candidate_matches_slug "${candidate_path##*/}" "${slug_key}"; then
      add_plan_candidate "worktree" "${attached_branch:-detached}" "${candidate_path}" "similar-worktree-path"
    fi
  done < <(iter_git_worktrees)

  while IFS= read -r candidate_branch; do
    if [[ -z "${candidate_branch}" ]]; then
      continue
    fi

    if [[ "${candidate_branch}" == "${branch_name}" ]]; then
      add_plan_candidate "local-branch" "${candidate_branch}" "" "exact-local-branch"
      continue
    fi

    if candidate_matches_slug "${candidate_branch}" "${slug_key}"; then
      add_plan_candidate "local-branch" "${candidate_branch}" "" "similar-local-branch"
    fi
  done < <(iter_local_branches)

  while IFS= read -r candidate_branch; do
    if [[ -z "${candidate_branch}" ]]; then
      continue
    fi

    if [[ "${candidate_branch}" == "origin/${branch_name}" ]]; then
      add_plan_candidate "remote-branch" "${candidate_branch}" "" "exact-remote-branch"
      continue
    fi

    if candidate_matches_slug "${candidate_branch}" "${slug_key}"; then
      add_plan_candidate "remote-branch" "${candidate_branch}" "" "similar-remote-branch"
    fi
  done < <(iter_remote_branches)
}

find_bd_worktree_by_path() {
  local search_path="$1"
  local output=""
  local exit_code=0
  local bd_command=""
  local line=""
  local record_path=""

  if ! bd_command="$(resolve_bd_command)" || ! command -v jq >/dev/null 2>&1; then
    printf '__PROBE_STATE__\tprobe_unavailable\n'
    return 0
  fi

  set +e
  output="$(
    cd "${resolved_repo_root}" && "${bd_command}" worktree list --json 2>/dev/null \
      | jq -r '
        .[]
        | [(.name // ""), (.path // ""), (.branch // ""), (.beads_state // ""), (.redirect_to // "")]
        | @tsv
      '
  )"
  exit_code=$?
  set -e

  if [[ "${exit_code}" -eq 0 ]]; then
    printf '__PROBE_STATE__\tok\n'
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      record_path="$(printf '%s\n' "${line}" | cut -f2)"
      if paths_refer_to_same_location "${record_path}" "${search_path}"; then
        printf '%s\n' "${line}"
        break
      fi
    done <<< "${output}"
    return 0
  fi

  printf '__PROBE_STATE__\tprobe_unavailable\n'
}

extract_bd_worktree_record_from_payload() {
  local payload="$1"
  local line=""

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    if [[ "${line}" == "__PROBE_STATE__"$'\t'* ]]; then
      continue
    fi
    printf '%s\n' "${line}"
    return 0
  done <<< "${payload}"

  return 1
}

discover_target_state() {
  local git_record=""
  local bd_payload=""
  local bd_record=""
  local bd_path=""
  local git_path=""
  local git_branch=""
  local bd_name=""
  local bd_branch=""
  local bd_state=""
  local bd_redirect=""
  local line=""

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
    bd_payload="$(find_bd_worktree_by_path "${discovered_worktree_path}" || true)"
  elif [[ -n "${target_path}" ]]; then
    bd_payload="$(find_bd_worktree_by_path "${target_path}" || true)"
  fi

  if [[ -n "${bd_payload}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      if [[ "${line}" == "__PROBE_STATE__"$'\t'* ]]; then
        discovered_beads_probe_state="${line#*$'\t'}"
        continue
      fi

      bd_record="${line}"
      break
    done <<< "${bd_payload}"
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

discover_beads_runtime_state() {
  local worktree_path=""
  local beads_dir=""
  local config_path=""
  local issues_path=""
  local has_local_runtime="false"
  local has_runtime_shell="false"
  local doctor_output=""

  discovered_beads_runtime_state=""
  discovered_beads_runtime_probe_state="not_run"
  discovered_beads_runtime_reason=""

  if [[ -n "${discovered_worktree_path}" && -d "${discovered_worktree_path}" ]]; then
    worktree_path="${discovered_worktree_path}"
  elif [[ -n "${target_path}" && -d "${target_path}" ]]; then
    worktree_path="${target_path}"
  else
    return 0
  fi

  beads_dir="${worktree_path}/.beads"
  config_path="${beads_dir}/config.yaml"
  issues_path="${beads_dir}/issues.jsonl"

  if [[ ! -f "${config_path}" ]]; then
    discovered_beads_runtime_state="missing"
    discovered_beads_runtime_probe_state="filesystem"
    discovered_beads_runtime_reason="No local .beads/config.yaml was found in the target worktree."
    return 0
  fi

  if beads_resolve_has_local_runtime "${beads_dir}"; then
    has_local_runtime="true"
  fi
  if beads_resolve_has_runtime_shell "${beads_dir}"; then
    has_runtime_shell="true"
  fi

  if [[ "${has_local_runtime}" == "true" ]]; then
    if run_bd_probe_for_path "${worktree_path}" true status; then
      if [[ "${WORKTREE_READY_LAST_BD_TIMED_OUT}" == "true" ]]; then
        discovered_beads_runtime_state="probe_unavailable"
        discovered_beads_runtime_probe_state="timed_out"
        discovered_beads_runtime_reason="The local plain bd status probe timed out before the target worktree proved runtime health."
        return 0
      fi

      if [[ "${WORKTREE_READY_LAST_BD_RC}" -eq 0 ]]; then
        discovered_beads_runtime_state="healthy"
        discovered_beads_runtime_probe_state="ok"
        discovered_beads_runtime_reason="The local plain bd status probe opened the target runtime successfully."
        return 0
      fi
    else
      discovered_beads_runtime_state="probe_unavailable"
      discovered_beads_runtime_probe_state="probe_unavailable"
      discovered_beads_runtime_reason="The local plain bd status probe could not be executed from this session."
      return 0
    fi

    if run_system_bd_probe_for_path "${worktree_path}" true doctor --json; then
      if [[ "${WORKTREE_READY_LAST_BD_TIMED_OUT}" == "true" ]]; then
        discovered_beads_runtime_state="probe_unavailable"
        discovered_beads_runtime_probe_state="timed_out"
        discovered_beads_runtime_reason="The fallback system bd doctor probe timed out before runtime health could be confirmed."
        return 0
      fi

      doctor_output="${WORKTREE_READY_LAST_BD_OUTPUT}"
      if [[ "${doctor_output}" == *'database "beads" not found'* || "${doctor_output}" == *'metadata.json is missing'* ]]; then
        discovered_beads_runtime_state="runtime_bootstrap_required"
        discovered_beads_runtime_probe_state="doctor"
        discovered_beads_runtime_reason="The local runtime exists only as a partial Dolt shell; the named 'beads' DB is not materialized yet."
        return 0
      fi
    fi

    discovered_beads_runtime_state="probe_unavailable"
    discovered_beads_runtime_probe_state="status_failed"
    discovered_beads_runtime_reason="The local runtime exists, but the current session could not prove that plain bd can read it safely."
    return 0
  fi

  if [[ "${has_runtime_shell}" == "true" || ! -f "${issues_path}" ]]; then
    discovered_beads_runtime_state="runtime_bootstrap_required"
    discovered_beads_runtime_probe_state="filesystem"
    discovered_beads_runtime_reason="A local Dolt-backed Beads runtime shell exists, but the named 'beads' database is not materialized yet."
    return 0
  fi

  discovered_beads_runtime_state="partial_foundation"
  discovered_beads_runtime_probe_state="filesystem"
  discovered_beads_runtime_reason="Local Beads foundation files exist, but no local runtime is materialized yet."
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
    guard_probe_status="script_unavailable"
    guard_state="unknown"
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
    guard_probe_status="probe_unavailable"
    guard_state="unknown"
    return 0
  fi

  guard_probe_status="ok"
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
    environment_probe_status="not_required"
    environment_state="no_envrc"
    return 0
  fi

  if ! command -v direnv >/dev/null 2>&1; then
    environment_probe_status="tool_unavailable"
    environment_state="unknown"
    return 0
  fi

  set +e
  output="$(
    cd "${environment_probe_path}" && direnv export json 2>&1
  )"
  exit_code=$?
  set -e

  if [[ "${output}" == *"is blocked. Run \`direnv allow\` to approve its content"* ]]; then
    environment_probe_status="ok"
    environment_state="approval_needed"
    return 0
  fi

  if [[ "${output}" == *"/direnv/allow/"* && ( "${output}" == *"operation not permitted"* || "${output}" == *"permission denied"* ) ]]; then
    environment_probe_status="ok"
    environment_state="approval_needed"
    return 0
  fi

  if [[ "${exit_code}" -eq 0 ]]; then
    environment_probe_status="ok"
    environment_state="approved_or_not_required"
    return 0
  fi

  environment_probe_status="probe_unavailable"
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
  report_beads_runtime_state="unknown"
  report_beads_runtime_reason=""
  report_handoff_mode="manual"
  report_requested_handoff_mode="${handoff_profile}"
  report_topology_state="${topology_registry_state}"
  report_phase="unknown"
  report_boundary="none"
  report_final_state="blocked_action_required"
  report_approval_required="false"
  report_launch_command=""
  report_repair_command=""
  report_pending_work=""
  report_phase_b_seed_payload=""
  report_worktree_action="unchanged"
  report_issue_title=""
  report_bootstrap_source_ref=""
  report_close_action="skip"
  report_close_command=""
  report_local_branch_action="not_requested"
  report_remote_branch_action="not_requested"
  report_merge_check="not_requested"
  report_default_branch_name=""
  report_cleanup_reconcile_required="false"
  report_next_steps=()
  report_warnings=()
  report_issue_artifacts=()
  report_bootstrap_paths=()
}

set_report_target() {
  report_worktree_path="${target_path:-n/a}"
  report_path_preview="${path_preview:-n/a}"
  report_branch_name="${branch:-n/a}"
  report_issue_id="$(resolve_report_issue_id)"
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
  if [[ -n "${discovered_beads_runtime_state}" ]]; then
    report_beads_runtime_state="${discovered_beads_runtime_state}"
  fi
  if [[ -n "${discovered_beads_runtime_reason}" ]]; then
    report_beads_runtime_reason="${discovered_beads_runtime_reason}"
  fi

  if [[ -n "${discovered_worktree_path}" && -n "${target_path}" && "${discovered_worktree_path}" != "${target_path}" ]]; then
    if [[ "${mode}" == "doctor" && "${path_preview}" != "${target_path}" ]]; then
      :
    elif [[ "${branch_resolution_state}" == "resolved" ]]; then
      add_warning "Branch '${report_branch_name}' is already attached at ${discovered_worktree_path}"
    else
      add_warning "Discovery found an existing worktree at ${discovered_worktree_path}"
    fi
  fi

  if [[ -n "${discovered_redirect_target}" || "${discovered_beads_state}" == "redirected" ]]; then
    add_warning "Discovery found beads redirect metadata for the target worktree; localize it before running plain bd there"
  fi

  if [[ "${discovered_beads_probe_state}" == "probe_unavailable" ]]; then
    add_warning "Beads worktree state could not be probed from this session."
  fi

  case "${discovered_beads_runtime_state}" in
    runtime_bootstrap_required)
      add_warning "${discovered_beads_runtime_reason:-The local Beads runtime needs bootstrap repair before handoff.}"
      ;;
    partial_foundation)
      add_warning "${discovered_beads_runtime_reason:-The local Beads foundation exists, but no local runtime is materialized yet.}"
      ;;
    probe_unavailable)
      add_warning "${discovered_beads_runtime_reason:-The target Beads runtime could not be verified from this session.}"
      ;;
  esac
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

  case "${guard_probe_status}" in
    script_unavailable)
      add_warning "Guard probe script is not available in the target worktree."
      ;;
    probe_unavailable)
      add_warning "Guard probe could not be executed from this session."
      ;;
  esac
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

  case "${environment_probe_status}" in
    tool_unavailable)
      add_warning "direnv is not available from this session; environment readiness could not be confirmed."
      ;;
    probe_unavailable)
      add_warning "Environment readiness could not be probed from this session."
      ;;
  esac
}

apply_topology_probe_to_report() {
  report_topology_state="${topology_registry_state}"

  if [[ "${topology_registry_state}" == "stale" ]]; then
    add_warning "Git topology registry is stale; the tracked remote-governance snapshot is behind live git discovery. Local worktree and local-only branch topology remain live-only here; dispatch scripts/git-topology-registry.sh publish later if you need the markdown snapshot updated."
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

  if [[ "${report_beads_state}" == "redirected" ]]; then
    report_status="action_required"
    add_warning "The target worktree still points at a redirected Beads tracker."
    return 0
  fi

  if [[ "${report_beads_runtime_state}" == "runtime_bootstrap_required" || "${report_beads_runtime_state}" == "partial_foundation" ]]; then
    report_status="action_required"
    return 0
  fi

  if report_worktree_path_exists; then
    if [[ "${report_beads_state}" == "missing" && -n "${discovered_worktree_path}" ]]; then
      add_warning "The target worktree exists, but worktree-local Beads ownership could not be confirmed."
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

set_doctor_status() {
  if [[ "${branch_resolution_state}" == "missing" ]]; then
    report_status="action_required"
    return 0
  fi

  if ! report_worktree_path_exists; then
    report_status="action_required"
    return 0
  fi

  if [[ "${report_guard_state}" == "drift" ]]; then
    report_status="drift_detected"
    return 0
  fi

  if [[ "${report_guard_state}" == "missing" ]]; then
    report_status="action_required"
    return 0
  fi

  if [[ "${report_beads_state}" == "redirected" ]]; then
    report_status="action_required"
    add_warning "The target worktree still points at a redirected Beads tracker."
    return 0
  fi

  if [[ "${report_beads_runtime_state}" == "runtime_bootstrap_required" || "${report_beads_runtime_state}" == "partial_foundation" ]]; then
    report_status="action_required"
    return 0
  fi

  if [[ "${report_beads_state}" == "missing" && "${discovered_beads_probe_state}" == "ok" ]]; then
    report_status="action_required"
    add_warning "The target worktree exists, but worktree-local Beads ownership could not be confirmed."
    return 0
  fi

  case "${report_env_state}" in
    approval_needed)
      report_status="needs_env_approval"
      ;;
    approved_or_not_required|no_envrc)
      if [[ "${guard_probe_status}" == "ok" ]]; then
        report_status="ready_for_codex"
      else
        report_status="created"
      fi
      ;;
    *)
      report_status="created"
      ;;
  esac
}

set_finish_status() {
  if [[ "${branch_resolution_state}" == "missing" ]]; then
    report_status="action_required"
    return 0
  fi

  if [[ -z "${report_branch_name}" || "${report_branch_name}" == "n/a" ]]; then
    report_status="action_required"
    add_warning "The target branch could not be resolved for finish."
    return 0
  fi

  if ! report_worktree_path_exists; then
    report_status="action_required"
    return 0
  fi

  if [[ "${report_guard_state}" == "drift" ]]; then
    report_status="drift_detected"
    return 0
  fi

  if [[ "${report_beads_state}" == "redirected" ]]; then
    report_status="action_required"
    add_warning "The target worktree still points at a redirected Beads tracker."
    return 0
  fi

  if [[ "${report_beads_runtime_state}" == "runtime_bootstrap_required" || "${report_beads_runtime_state}" == "partial_foundation" ]]; then
    report_status="action_required"
    return 0
  fi

  if [[ "${report_beads_state}" == "missing" && "${discovered_beads_probe_state}" == "ok" && "${report_worktree_path}" != "${resolved_repo_root}" ]]; then
    report_status="action_required"
    add_warning "The target worktree exists, but worktree-local Beads ownership could not be confirmed."
    return 0
  fi

  report_status="finish_ready"
}

set_handoff_contract() {
  local mode_name="$1"

  report_phase="${mode_name}"
  report_approval_required="false"
  report_launch_command=""
  report_repair_command=""
  report_pending_work=""

  case "${mode_name}" in
    create)
      report_boundary="stop_after_create"
      report_worktree_action="created"
      ;;
    attach)
      report_boundary="stop_after_attach"
      if [[ -n "${discovered_worktree_path}" ]]; then
        report_worktree_action="reused"
      else
        report_worktree_action="attached"
      fi
      ;;
    doctor)
      report_boundary="none"
      report_worktree_action="diagnosed"
      ;;
    handoff)
      report_boundary="stop_after_handoff"
      report_worktree_action="unchanged"
      ;;
    *)
      report_boundary="none"
      report_worktree_action="unchanged"
      ;;
  esac

  case "${report_status}" in
    ready_for_codex)
      report_final_state="handoff_ready"
      ;;
    needs_env_approval)
      report_final_state="handoff_needs_env_approval"
      report_approval_required="true"
      ;;
    created)
      report_final_state="handoff_needs_manual_readiness"
      ;;
    drift_detected)
      report_final_state="blocked_guard_drift"
      report_repair_command="./scripts/git-session-guard.sh --refresh"
      ;;
    action_required)
      if [[ "${branch_resolution_state}" == "missing" ]]; then
        report_final_state="blocked_missing_branch"
        report_repair_command="Create or fetch the branch '${branch}' before using attach or start --existing"
      else
        report_final_state="blocked_action_required"
      fi
      ;;
    *)
      report_final_state="blocked_action_required"
      ;;
  esac

  if [[ "${report_env_state}" == "approval_needed" ]]; then
    report_approval_required="true"
  fi

  if [[ "${report_handoff_mode}" != "manual" && -n "${handoff_launch_command}" ]]; then
    report_final_state="handoff_launched"
    report_launch_command="${handoff_launch_command}"
  fi

  case "${mode_name}" in
    create|attach|handoff)
      if [[ -n "${pending_summary}" ]]; then
        report_pending_work="${pending_summary}"
      fi
      if [[ -n "${phase_b_seed_payload}" ]]; then
        report_phase_b_seed_payload="${phase_b_seed_payload}"
      fi
      ;;
  esac
}

set_command_exit_code_from_readiness() {
  case "${report_final_state}" in
    handoff_ready|handoff_needs_env_approval|handoff_needs_manual_readiness|handoff_launched|finish_ready)
      command_exit_code=0
      ;;
    blocked_guard_drift)
      command_exit_code=21
      ;;
    blocked_missing_branch)
      command_exit_code=22
      ;;
    blocked_action_required)
      command_exit_code=23
      ;;
    *)
      command_exit_code=30
      ;;
  esac
}

set_command_exit_code_from_cleanup() {
  case "${report_final_state}" in
    cleanup_complete)
      command_exit_code=0
      ;;
    cleanup_blocked)
      command_exit_code=23
      ;;
    *)
      command_exit_code=30
      ;;
  esac
}

set_readiness_next_steps() {
  local mode_name="$1"
  local bootstrap_command=""
  local plain_bd_bootstrap=""
  local phase_a_create_command=""

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
      add_next_step "cd $(shell_quote "${report_worktree_path}")"
      if plain_bd_bootstrap="$(build_plain_bd_bootstrap_command_for_path "${report_worktree_path}")"; then
        add_next_step "${plain_bd_bootstrap}"
      fi
      if bootstrap_command="$(build_bootstrap_import_command)"; then
        add_next_step "${bootstrap_command}"
      fi
      add_next_step "codex"
      ;;
    needs_env_approval)
      add_next_step "cd $(shell_quote "${report_worktree_path}")"
      if plain_bd_bootstrap="$(build_plain_bd_bootstrap_command_for_path "${report_worktree_path}")"; then
        add_next_step "${plain_bd_bootstrap}"
      fi
      if bootstrap_command="$(build_bootstrap_import_command)"; then
        add_next_step "${bootstrap_command}"
      fi
      add_next_step "direnv allow"
      add_next_step "codex"
      ;;
    created)
      add_next_step "cd $(shell_quote "${report_worktree_path}")"
      if plain_bd_bootstrap="$(build_plain_bd_bootstrap_command_for_path "${report_worktree_path}")"; then
        add_next_step "${plain_bd_bootstrap}"
      fi
      if bootstrap_command="$(build_bootstrap_import_command)"; then
        add_next_step "${bootstrap_command}"
      fi
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
            if [[ "${report_beads_runtime_state}" == "runtime_bootstrap_required" ]]; then
              add_next_step "/usr/local/bin/bd doctor --json"
              add_next_step "./scripts/beads-worktree-localize.sh --path ."
            elif [[ "${report_beads_runtime_state}" == "partial_foundation" || "${report_beads_state}" == "redirected" ]]; then
              add_next_step "./scripts/beads-worktree-localize.sh"
            else
              add_next_step "Inspect the existing worktree and fix the reported prerequisites"
            fi
          else
            if [[ "${mode_name}" == "create" ]] && phase_a_create_command="$(build_phase_a_create_command_for_target "${branch}" "${target_path}")"; then
              add_warning "worktree-ready create is a post-Phase-A handoff helper; it does not allocate the branch or git worktree by itself."
              report_repair_command="${phase_a_create_command}"
              add_next_step "${phase_a_create_command}"
            else
              add_next_step "Retry the managed worktree flow from the invoking worktree after fixing the reported prerequisites"
            fi
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

set_doctor_next_steps() {
  local worktree_target=""
  local refspec=""
  local plain_bd_bootstrap=""

  worktree_target="${report_worktree_path}"

  if [[ "${report_requested_handoff_mode}" != "manual" ]]; then
    add_warning "Doctor mode ignores automatic handoff requests and returns diagnostics only."
  fi

  if [[ "${branch_resolution_state}" == "missing" ]]; then
    refspec="${branch}:${branch}"
    add_next_step "git fetch origin $(shell_quote "${refspec}")"
    return 0
  fi

  if ! report_worktree_path_exists; then
    if [[ -n "${branch}" ]]; then
      add_next_step "Use command-worktree attach $(shell_quote "${branch}") from the invoking worktree"
    elif [[ -n "${target_path}" ]]; then
      add_next_step "Inspect the current repository context and rerun doctor from the invoking worktree with a managed attach path"
    else
      add_next_step "Inspect the current repository context and retry doctor with --branch or --path"
    fi
    return 0
  fi

  if [[ "${report_guard_state}" == "drift" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/git-session-guard.sh --refresh"
  elif [[ "${report_beads_runtime_state}" == "runtime_bootstrap_required" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && /usr/local/bin/bd doctor --json"
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/beads-worktree-localize.sh --path ."
  elif [[ "${report_beads_runtime_state}" == "partial_foundation" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/beads-worktree-localize.sh --path ."
  elif [[ "${report_guard_state}" == "missing" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/git-session-guard.sh --refresh"
  elif [[ "${guard_probe_status}" == "script_unavailable" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && inspect scripts/git-session-guard.sh availability"
  elif [[ "${guard_probe_status}" == "probe_unavailable" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && inspect ./scripts/git-session-guard.sh --status"
  fi

  if [[ "${report_beads_state}" == "missing" && "${discovered_beads_probe_state}" == "ok" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/beads-worktree-localize.sh --path ."
  elif [[ "${report_beads_state}" == "redirected" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/beads-worktree-localize.sh --path ."
  fi

  case "${report_env_state}" in
    approval_needed)
      add_next_step "cd $(shell_quote "${worktree_target}") && direnv allow"
      ;;
    unknown)
      case "${environment_probe_status}" in
        tool_unavailable)
          add_next_step "Install direnv or launch the session from an environment where direnv is available"
          ;;
        probe_unavailable)
          add_next_step "cd $(shell_quote "${worktree_target}") && inspect .envrc readiness manually"
          ;;
      esac
      ;;
  esac

  if [[ "${#report_next_steps[@]}" -gt 0 ]]; then
    return 0
  fi

  case "${report_status}" in
    ready_for_codex)
      if plain_bd_bootstrap="$(build_plain_bd_bootstrap_command_for_path "${worktree_target}")"; then
        add_next_step "cd $(shell_quote "${worktree_target}")"
        add_next_step "${plain_bd_bootstrap}"
        add_next_step "codex"
      else
        add_next_step "cd $(shell_quote "${worktree_target}") && codex"
      fi
      ;;
    created)
      add_next_step "cd $(shell_quote "${worktree_target}")"
      add_next_step "Run the reported prerequisite checks and then launch codex"
      ;;
    *)
      add_next_step "cd $(shell_quote "${worktree_target}")"
      add_next_step "Inspect the reported warnings and retry doctor once they are fixed"
      ;;
  esac
}

set_command_exit_code_from_plan() {
  case "${planning_decision}" in
    create_clean|attach_existing_branch|reuse_existing)
      command_exit_code=0
      ;;
    needs_clarification)
      command_exit_code=10
      ;;
    *)
      command_exit_code=30
      ;;
  esac
}

add_next_step() {
  local step_text="$1"

  if [[ -n "${step_text}" ]]; then
    report_next_steps+=("${step_text}")
  fi
}

set_finish_contract() {
  report_phase="finish"
  report_boundary="stop_before_finish"
  report_worktree_action="finish_prepared"
  report_repair_command=""
  report_pending_work=""
  report_close_action="skip"
  report_close_command=""

  case "${report_status}" in
    finish_ready)
      report_final_state="finish_ready"
      ;;
    drift_detected)
      report_final_state="blocked_guard_drift"
      report_repair_command="./scripts/git-session-guard.sh --refresh"
      ;;
    action_required)
      if [[ "${branch_resolution_state}" == "missing" ]]; then
        report_final_state="blocked_missing_branch"
        report_repair_command="Create or fetch the branch '${branch}' before retrying finish"
      else
        report_final_state="blocked_action_required"
      fi
      ;;
    *)
      report_final_state="blocked_action_required"
      ;;
  esac

  if [[ "${report_status}" == "finish_ready" ]]; then
    if report_close_command="$(build_finish_close_command)"; then
      report_close_action="close"
    else
      report_close_action="skip"
      add_warning "Issue: n/a; skip bd close for ordinary finish."
    fi
  elif [[ "${report_final_state}" == blocked_* ]]; then
    report_close_action="blocked"
  fi
}

set_finish_next_steps() {
  local worktree_target="${report_worktree_path}"
  local plain_bd_bootstrap=""
  local close_command=""
  local refspec=""

  if [[ "${branch_resolution_state}" == "missing" ]]; then
    refspec="${branch}:${branch}"
    add_next_step "git fetch origin $(shell_quote "${refspec}")"
    return 0
  fi

  if [[ -z "${report_branch_name}" || "${report_branch_name}" == "n/a" ]]; then
    if [[ "${worktree_target}" != "n/a" ]]; then
      add_next_step "cd $(shell_quote "${worktree_target}")"
    fi
    add_next_step "Inspect the target branch context and retry finish once the branch is known"
    return 0
  fi

  if ! report_worktree_path_exists; then
    if [[ -n "${branch}" ]]; then
      add_next_step "Use command-worktree attach $(shell_quote "${branch}") from the invoking worktree"
    elif [[ -n "${target_path}" ]]; then
      add_next_step "Inspect the current repository context and rerun finish from the target worktree path"
    else
      add_next_step "Inspect the current repository context and retry finish with --branch or --path"
    fi
    return 0
  fi

  if [[ "${report_guard_state}" == "drift" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/git-session-guard.sh --refresh"
    return 0
  fi

  if [[ "${report_beads_runtime_state}" == "runtime_bootstrap_required" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && /usr/local/bin/bd doctor --json"
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/beads-worktree-localize.sh --path ."
    return 0
  fi

  if [[ "${report_beads_runtime_state}" == "partial_foundation" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/beads-worktree-localize.sh --path ."
    return 0
  fi

  if [[ "${report_beads_state}" == "missing" && "${discovered_beads_probe_state}" == "ok" && "${worktree_target}" != "${resolved_repo_root}" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/beads-worktree-localize.sh --path ."
    return 0
  fi

  if [[ "${report_beads_state}" == "redirected" ]]; then
    add_next_step "cd $(shell_quote "${worktree_target}") && ./scripts/beads-worktree-localize.sh --path ."
    return 0
  fi

  add_next_step "cd $(shell_quote "${worktree_target}")"
  if plain_bd_bootstrap="$(build_plain_bd_bootstrap_command_for_path "${worktree_target}")"; then
    add_next_step "${plain_bd_bootstrap}"
  fi
  add_next_step "bd preflight --check"
  review_command="$(build_finish_review_command "${worktree_target}")"
  add_next_step "${review_command}"
  add_next_step "$(build_finish_commit_command)"
  add_next_step "git pull --rebase"
  add_next_step "${review_command}"
  add_next_step "git push -u origin $(shell_quote "${report_branch_name}")"

  if close_command="$(build_finish_close_command)"; then
    add_next_step "${close_command}"
  fi

  add_warning "If bd preflight --check is unavailable, run the project default fast checks before closing."
}

execute_cleanup_worktree_action() {
  local cleanup_path="${report_worktree_path:-${target_path:-}}"
  local record=""
  local record_branch=""
  local prunable_reason=""
  local locked_reason=""
  local bd_command=""
  local output=""
  local fallback_branch=""
  local fallback_output=""
  local fallback_rc=0
  local fallback_merge_check=""
  local fallback_default_branch_name=""
  local fallback_bd_record=""
  local fallback_bd_lookup_path=""
  local saved_merge_check=""
  local saved_default_branch_name=""
  local default_branch_name=""
  local rc=0

  if [[ -z "${cleanup_path}" || "${cleanup_path}" == "n/a" ]]; then
    report_worktree_action="already_missing"
    return 0
  fi

  if [[ "${cleanup_path}" == "${resolved_canonical_root}" || "${cleanup_path}" == "${resolved_repo_root}" ]]; then
    report_worktree_action="blocked"
    report_repair_command="Refusing to remove the canonical root worktree"
    add_warning "Cleanup refuses to remove the canonical root worktree."
    add_next_step "Retry cleanup with a linked worktree path instead of ${cleanup_path}"
    return 1
  fi

  record="$(git_worktree_record_for_path "${cleanup_path}" || true)"
  if [[ -z "${record}" ]]; then
    if [[ -d "${cleanup_path}" ]]; then
      report_worktree_action="blocked"
      add_warning "Target path exists, but git does not recognize it as a managed linked worktree."
      add_next_step "Inspect $(shell_quote "${cleanup_path}") and retry cleanup with a managed linked worktree target"
      return 1
    fi

    report_worktree_action="already_missing"
    return 0
  fi

  IFS=$'\t' read -r _ record_branch prunable_reason locked_reason <<< "${record}"
  if [[ -n "${locked_reason}" ]]; then
    report_worktree_action="blocked"
    add_warning "Cleanup refuses to remove a locked worktree at ${cleanup_path}."
    add_next_step "Inspect git worktree lock state for $(shell_quote "${cleanup_path}") and retry cleanup after unlocking it"
    return 1
  fi

  if [[ ! -d "${cleanup_path}" ]]; then
    if [[ -n "${prunable_reason}" ]]; then
      set +e
      output="$(git -C "${resolved_repo_root}" worktree prune 2>&1)"
      rc=$?
      set -e

      if [[ "${rc}" -eq 0 ]] && ! git_worktree_record_for_path "${cleanup_path}" >/dev/null 2>&1; then
        report_worktree_action="pruned"
        return 0
      fi

      report_worktree_action="blocked"
      add_warning "git worktree prune did not clear the stale worktree entry for ${cleanup_path}."
      if [[ -n "${output}" ]]; then
        add_warning "$(printf '%s' "${output}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
      fi
      add_next_step "git -C $(shell_quote "${resolved_repo_root}") worktree prune"
      return 1
    fi

    report_worktree_action="already_missing"
    return 0
  fi

  bd_command="$(resolve_bd_command_for_path "${resolved_repo_root}")" || {
    report_worktree_action="blocked"
    add_warning "Plain bd is unavailable from the canonical root session."
    add_next_step "export PATH=$(shell_quote "${resolved_repo_root}/bin"):\$PATH"
    add_next_step "bd worktree remove $(shell_quote "${cleanup_path}")"
    return 1
  }

  set +e
  output="$(
    cd "${resolved_repo_root}" &&
    "${bd_command}" worktree remove "${cleanup_path}" 2>&1
  )"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    fallback_branch="$(resolve_cleanup_target_branch_name || true)"
    if [[ -z "${fallback_branch}" ]]; then
      fallback_branch="${record_branch}"
    fi
    if cleanup_output_indicates_false_unpushed_guard "${output}" \
      && [[ -n "${fallback_branch}" ]] \
      && worktree_has_clean_status "${cleanup_path}"; then
      saved_merge_check="${report_merge_check}"
      saved_default_branch_name="${report_default_branch_name}"
      default_branch_name="$(resolve_default_branch_name)"
      if resolve_cleanup_merge_proof "${fallback_branch}" "${default_branch_name}" "true"; then
        fallback_merge_check="${report_merge_check}"
        fallback_default_branch_name="${report_default_branch_name}"
        report_merge_check="${saved_merge_check}"
        report_default_branch_name="${saved_default_branch_name}"

        set +e
        fallback_output="$(git -C "${resolved_repo_root}" worktree remove "${cleanup_path}" 2>&1)"
        fallback_rc=$?
        set -e

        if [[ "${fallback_rc}" -eq 0 ]] && wait_for_worktree_removal "${cleanup_path}"; then
          report_worktree_action="removed"
          report_merge_check="${fallback_merge_check}"
          report_default_branch_name="${fallback_default_branch_name}"
          add_warning "bd worktree remove reported unpushed commits for merged clean worktree ${cleanup_path}; git worktree remove fallback succeeded."
          fallback_bd_lookup_path="${report_worktree_path:-${discovered_worktree_path:-${cleanup_path}}}"
          fallback_bd_record="$(find_bd_worktree_by_path "${fallback_bd_lookup_path}" || true)"
          fallback_bd_record="$(extract_bd_worktree_record_from_payload "${fallback_bd_record}" || true)"
          if [[ -n "${fallback_bd_record}" ]]; then
            report_cleanup_reconcile_required="true"
            report_repair_command="cd $(shell_quote "${resolved_repo_root}") && bd worktree remove $(shell_quote "${cleanup_path}")"
            add_warning "Beads still reports ${cleanup_path} after git-only fallback removal; rerun bd cleanup to reconcile local worktree metadata."
            add_next_step "cd $(shell_quote "${resolved_repo_root}")"
            add_next_step "bd worktree remove $(shell_quote "${cleanup_path}")"
          fi
          return 0
        fi

        report_merge_check="${fallback_merge_check}"
        report_default_branch_name="${fallback_default_branch_name}"
        if [[ -n "${fallback_output}" ]]; then
          add_warning "$(printf '%s' "${fallback_output}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
        fi
      fi
    fi

    report_worktree_action="blocked"
    add_warning "bd worktree remove failed for ${cleanup_path}."
    if [[ -n "${output}" ]]; then
      add_warning "$(printf '%s' "${output}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    fi
    add_next_step "cd $(shell_quote "${resolved_repo_root}")"
    add_next_step "bd worktree remove $(shell_quote "${cleanup_path}")"
    if worktree_path_is_prunable "${cleanup_path}"; then
      add_next_step "git worktree prune"
    fi
    return 1
  fi

  if wait_for_worktree_removal "${cleanup_path}"; then
    report_worktree_action="removed"
    return 0
  fi

  if worktree_path_is_prunable "${cleanup_path}"; then
    set +e
    output="$(git -C "${resolved_repo_root}" worktree prune 2>&1)"
    rc=$?
    set -e
    if [[ "${rc}" -eq 0 ]] && ! git_worktree_record_for_path "${cleanup_path}" >/dev/null 2>&1; then
      report_worktree_action="pruned"
      return 0
    fi
  fi

  report_worktree_action="blocked"
  add_warning "Cleanup did not observe the worktree entry disappear after bd worktree remove."
  add_next_step "git -C $(shell_quote "${resolved_repo_root}") worktree list --porcelain"
  add_next_step "git -C $(shell_quote "${resolved_repo_root}") worktree prune"
  return 1
}

execute_cleanup_branch_actions() {
  local cleanup_branch=""
  local default_branch_name=""
  local output=""
  local local_delete_flag="-d"
  local local_only_branch_delete_allowed="false"
  local rc=0

  if [[ "${delete_branch_requested}" != "true" ]]; then
    report_local_branch_action="not_requested"
    report_remote_branch_action="not_requested"
    return 0
  fi

  report_local_branch_action="not_requested"
  report_remote_branch_action="not_requested"
  report_merge_check="not_requested"
  report_default_branch_name=""

  cleanup_branch="$(resolve_cleanup_target_branch_name || true)"

  if [[ -z "${cleanup_branch}" || "${cleanup_branch}" == "n/a" ]]; then
    report_local_branch_action="skipped"
    report_remote_branch_action="skipped"
    report_merge_check="missing_branch_name"
    add_warning "Cleanup cannot delete branches because no target branch name was resolved."
    add_next_step "Retry cleanup with --branch <name> if branch deletion is required"
    return 1
  fi

  if ! local_branch_exists "${cleanup_branch}" && ! remote_branch_exists "${cleanup_branch}"; then
    report_local_branch_action="already_missing"
    report_remote_branch_action="already_missing"
    report_merge_check="already_missing"
    return 0
  fi

  default_branch_name="$(resolve_default_branch_name)"
  report_default_branch_name="${default_branch_name}"

  if ! resolve_cleanup_merge_proof "${cleanup_branch}" "${default_branch_name}"; then
    if local_branch_exists "${cleanup_branch}" && ref_is_ancestor_of_remote_default "refs/heads/${cleanup_branch}" "${default_branch_name}"; then
      local_only_branch_delete_allowed="true"
      report_local_branch_action="not_requested"
      add_warning "Cleanup could not establish authoritative remote proof for '${cleanup_branch}', but local merged ancestry still allows local branch deletion while remote deletion stays blocked."
    else
      report_local_branch_action="skipped"
    fi
    if remote_branch_exists "${cleanup_branch}"; then
      report_remote_branch_action="blocked"
    else
      report_remote_branch_action="already_missing"
    fi

    add_warning "Cleanup could not establish merged proof for branch '${cleanup_branch}'."
    case "${report_merge_check}" in
      remote_refresh_failed)
        add_next_step "git -C $(shell_quote "${resolved_repo_root}") fetch --prune --no-tags origin"
        ;;
      github_unavailable)
        add_next_step "gh auth status -h github.com"
        ;;
      github_pr_ambiguous)
        add_warning "Multiple merged PR candidates matched the branch name; remote delete remains blocked until a single PR/head SHA is confirmed."
        ;;
      missing_branch_tip)
        add_warning "No local or remote branch tip is available to compare against merged PR metadata."
        ;;
    esac
    if remote_branch_exists "${cleanup_branch}" || local_branch_exists "${cleanup_branch}"; then
      add_next_step "git merge-base --is-ancestor $(shell_quote "refs/remotes/origin/${cleanup_branch}") $(shell_quote "refs/remotes/origin/${default_branch_name}")"
    fi
    if origin_uses_github; then
      add_next_step "cd $(shell_quote "${resolved_repo_root}") && gh pr list --state merged --head $(shell_quote "${cleanup_branch}") --json number,state,mergedAt,headRefName,headRefOid,baseRefName,url"
    fi
    if [[ "${local_only_branch_delete_allowed}" != "true" ]]; then
      return 1
    fi
  fi

  if local_branch_exists "${cleanup_branch}"; then
    if [[ "${report_merge_check}" == "github_pr_merged" ]]; then
      local_delete_flag="-D"
    fi
    set +e
    output="$(git -C "${resolved_repo_root}" branch "${local_delete_flag}" "${cleanup_branch}" 2>&1)"
    rc=$?
    set -e

    if [[ "${rc}" -eq 0 ]]; then
      report_local_branch_action="deleted"
    else
      report_local_branch_action="blocked"
      add_warning "git branch ${local_delete_flag} failed for ${cleanup_branch}."
      if [[ -n "${output}" ]]; then
        add_warning "$(printf '%s' "${output}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
      fi
      add_next_step "git -C $(shell_quote "${resolved_repo_root}") branch ${local_delete_flag} $(shell_quote "${cleanup_branch}")"
      return 1
    fi
  else
    report_local_branch_action="already_missing"
  fi

  if [[ "${local_only_branch_delete_allowed}" == "true" ]]; then
    return 1
  fi

  if remote_branch_exists "${cleanup_branch}"; then
    local remote_delete_fallback_output=""
    local remote_delete_fallback_rc=0
    local remote_delete_fallback_command=""
    set +e
    output="$(git -C "${resolved_repo_root}" push origin --delete "${cleanup_branch}" 2>&1)"
    rc=$?
    set -e

    if [[ "${rc}" -eq 0 ]]; then
      report_remote_branch_action="deleted"
    elif ! remote_branch_exists "${cleanup_branch}"; then
      report_remote_branch_action="deleted"
      add_warning "git push origin --delete returned non-zero for ${cleanup_branch}, but the remote-tracking ref disappeared anyway."
    else
      remote_delete_fallback_command="$(github_delete_ref_command "${cleanup_branch}" || true)"
      if [[ -n "${remote_delete_fallback_command}" ]]; then
        set +e
        remote_delete_fallback_output="$(delete_remote_branch_via_github_api "${cleanup_branch}" 2>&1)"
        remote_delete_fallback_rc=$?
        set -e
      else
        remote_delete_fallback_rc=1
      fi

      if [[ "${remote_delete_fallback_rc}" -eq 0 ]]; then
        report_remote_branch_action="deleted"
        add_warning "GitHub API fallback deleted remote branch '${cleanup_branch}' after git push origin --delete failed."
      else
        report_remote_branch_action="blocked"
        add_warning "git push origin --delete failed for ${cleanup_branch}."
        if [[ -n "${output}" ]]; then
          add_warning "$(printf '%s' "${output}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
        fi
        if [[ -n "${remote_delete_fallback_output}" ]]; then
          add_warning "$(printf '%s' "${remote_delete_fallback_output}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
        fi
        if [[ -n "${remote_delete_fallback_command}" ]]; then
          add_next_step "${remote_delete_fallback_command}"
        fi
        add_next_step "git -C $(shell_quote "${resolved_repo_root}") push origin --delete $(shell_quote "${cleanup_branch}")"
        return 1
      fi
    fi
  else
    report_remote_branch_action="already_missing"
  fi

  return 0
}

set_cleanup_contract() {
  report_phase="cleanup"
  report_boundary="none"

  if [[ "${report_cleanup_reconcile_required}" == "true" || "${report_worktree_action}" == "blocked" || "${report_local_branch_action}" == "blocked" || "${report_remote_branch_action}" == "blocked" || "${report_local_branch_action}" == "skipped" || "${report_remote_branch_action}" == "skipped" ]]; then
    report_status="cleanup_blocked"
    report_final_state="cleanup_blocked"
    return 0
  fi

  report_status="cleanup_complete"
  report_final_state="cleanup_complete"
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

render_fenced_bash_block() {
  local command_text=""

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  printf '```bash\n'
  for command_text in "$@"; do
    printf '%s\n' "${command_text}"
  done
  printf '```\n'
}

render_phase_b_seed_prompt() {
  if [[ -z "${report_pending_work}" || -n "${report_phase_b_seed_payload}" ]]; then
    return 0
  fi

  printf '```text\n'
  printf 'Phase B only.\n'
  printf 'Worktree: %s\n' "${report_worktree_path:-n/a}"
  printf 'Branch: %s\n' "${report_branch_name:-n/a}"
  printf 'Task: %s\n' "${report_pending_work}"
  printf 'Phase A is complete. Do not repeat worktree setup. Do not create or update issues, specs, or plans unless explicitly requested in the target session.\n'
  printf '```\n'
}

render_phase_b_seed_payload() {
  if [[ -z "${report_phase_b_seed_payload}" ]]; then
    return 0
  fi

  printf '```text\n'
  printf 'Phase B Seed Payload (deferred, not executed).\n'
  printf 'Worktree: %s\n' "${report_worktree_path:-n/a}"
  printf 'Branch: %s\n' "${report_branch_name:-n/a}"
  if [[ -n "${report_pending_work}" ]]; then
    printf 'Pending Summary: %s\n' "${report_pending_work}"
  fi
  printf 'Payload:\n'
  printf '%s\n' "${report_phase_b_seed_payload}"
  printf 'Phase A is complete. Do not repeat worktree setup in the originating session.\n'
  printf '```\n'
}

render_env_kv() {
  local key="$1"
  local value="${2:-}"
  printf '%s=%q\n' "${key}" "${value}"
}

render_env_array() {
  local prefix="$1"
  shift
  local items=("$@")
  local index=1

  render_env_kv "${prefix}_count" "${#items[@]}"
  for item in "${items[@]}"; do
    render_env_kv "${prefix}_${index}" "${item}"
    index=$((index + 1))
  done
}

render_plan_candidates() {
  local candidate=""
  local index=1
  local candidate_type=""
  local candidate_name=""
  local candidate_path=""
  local candidate_reason=""

  printf 'Candidates:\n'
  if [[ "${#planning_candidates[@]}" -eq 0 ]]; then
    printf '  1. none\n'
    return 0
  fi

  for candidate in "${planning_candidates[@]}"; do
    IFS=$'\t' read -r candidate_type candidate_name candidate_path candidate_reason <<< "${candidate}"
    printf '  %d. type=%s name=%s' "${index}" "${candidate_type}" "${candidate_name}"
    if [[ -n "${candidate_path}" && "${candidate_path}" != "-" ]]; then
      printf ' path=%s' "${candidate_path}"
    fi
    if [[ -n "${candidate_reason}" ]]; then
      printf ' reason=%s' "${candidate_reason}"
    fi
    printf '\n'
    index=$((index + 1))
  done
}

render_plan_report() {
  if [[ "${output_format}" == "env" ]]; then
    render_env_kv "schema" "worktree-plan/v1"
    render_env_kv "mode" "plan"
    render_env_kv "slug" "${request_slug:-n/a}"
    render_env_kv "issue" "${issue_id:-n/a}"
    render_env_kv "branch" "${branch:-n/a}"
    render_env_kv "preview" "${path_preview:-n/a}"
    render_env_kv "worktree" "${target_path:-n/a}"
    render_env_kv "decision" "${planning_decision}"
    if speckit_branching_enabled; then
      render_env_kv "speckit" "true"
    else
      render_env_kv "speckit" "false"
    fi
    render_env_kv "topology" "${topology_registry_state}"
    if [[ -n "${planning_question}" ]]; then
      render_env_kv "question" "${planning_question}"
    fi
    render_env_array "next" "${planning_next_steps[@]}"
    render_env_array "warning" "${planning_warnings[@]}"
    render_env_array "candidate" "${planning_candidates[@]}"
    return 0
  fi

  printf 'Mode: plan\n'
  printf 'Slug: %s\n' "${request_slug:-n/a}"
  printf 'Issue: %s\n' "${issue_id:-n/a}"
  printf 'Branch: %s\n' "${branch:-n/a}"
  printf 'Preview: %s\n' "${path_preview:-n/a}"
  printf 'Worktree: %s\n' "${target_path:-n/a}"
  printf 'Decision: %s\n' "${planning_decision}"
  if speckit_branching_enabled; then
    printf 'Speckit: true\n'
  else
    printf 'Speckit: false\n'
  fi
  printf 'Topology: %s\n' "${topology_registry_state}"
  if [[ -n "${planning_question}" ]]; then
    printf 'Question: %s\n' "${planning_question}"
  fi
  printf 'Next:\n'
  render_numbered_list "${planning_next_steps[@]}"
  render_plan_candidates
  render_warning_list "${planning_warnings[@]}"
}

render_readiness_report() {
  if [[ "${output_format}" == "env" ]]; then
    render_env_kv "schema" "worktree-handoff/v1"
    render_env_kv "phase" "${report_phase}"
    render_env_kv "boundary" "${report_boundary}"
    render_env_kv "final_state" "${report_final_state}"
    render_env_kv "worktree_action" "${report_worktree_action}"
    render_env_kv "worktree" "${report_worktree_path:-n/a}"
    render_env_kv "preview" "${report_path_preview:-n/a}"
    render_env_kv "branch" "${report_branch_name:-n/a}"
    render_env_kv "issue" "${report_issue_id:-n/a}"
    if [[ -n "${report_issue_title}" ]]; then
      render_env_kv "issue_title" "${report_issue_title}"
    fi
    render_env_kv "status" "${report_status}"
    render_env_kv "topology_state" "${report_topology_state}"
    render_env_kv "env_state" "${report_env_state}"
    render_env_kv "guard_state" "${report_guard_state}"
    render_env_kv "beads_state" "${report_beads_state}"
    render_env_kv "beads_runtime_state" "${report_beads_runtime_state}"
    if [[ -n "${report_beads_runtime_reason}" ]]; then
      render_env_kv "beads_runtime_reason" "${report_beads_runtime_reason}"
    fi
    render_env_kv "handoff_mode" "${report_handoff_mode}"
    render_env_kv "requested_handoff" "${report_requested_handoff_mode}"
    render_env_kv "approval_required" "${report_approval_required}"
    if [[ -n "${report_launch_command}" ]]; then
      render_env_kv "launch_command" "${report_launch_command}"
    fi
    if [[ -n "${report_repair_command}" ]]; then
      render_env_kv "repair_command" "${report_repair_command}"
    fi
    if [[ -n "${report_pending_work}" ]]; then
      render_env_kv "pending" "${report_pending_work}"
    fi
    if [[ -n "${report_phase_b_seed_payload}" ]]; then
      render_env_kv "phase_b_seed_payload" "${report_phase_b_seed_payload}"
    fi
    if [[ "${#report_issue_artifacts[@]}" -gt 0 ]]; then
      render_env_array "issue_artifact" "${report_issue_artifacts[@]}"
    fi
    if [[ -n "${report_bootstrap_source_ref}" ]]; then
      render_env_kv "bootstrap_source" "${report_bootstrap_source_ref}"
    fi
    if [[ "${#report_bootstrap_paths[@]}" -gt 0 ]]; then
      render_env_array "bootstrap_file" "${report_bootstrap_paths[@]}"
    fi
    render_env_array "next" "${report_next_steps[@]}"
    render_env_array "warning" "${report_warnings[@]}"
    return 0
  fi

  printf 'Worktree: %s\n' "${report_worktree_path:-n/a}"
  printf 'Preview: %s\n' "${report_path_preview:-n/a}"
  printf 'Branch: %s\n' "${report_branch_name:-n/a}"
  printf 'Issue: %s\n' "${report_issue_id:-n/a}"
  if [[ -n "${report_issue_title}" ]]; then
    printf 'Issue Title: %s\n' "${report_issue_title}"
  fi
  if [[ "${#report_issue_artifacts[@]}" -gt 0 ]]; then
    printf 'Issue Artifacts:\n'
    render_numbered_list "${report_issue_artifacts[@]}"
  fi
  if [[ -n "${report_bootstrap_source_ref}" && "${#report_bootstrap_paths[@]}" -gt 0 ]]; then
    printf 'Bootstrap Source: %s\n' "${report_bootstrap_source_ref}"
    printf 'Bootstrap Files:\n'
    render_numbered_list "${report_bootstrap_paths[@]}"
  fi
  printf 'Status: %s\n' "${report_status}"
  printf 'Phase: %s\n' "${report_phase}"
  printf 'Boundary: %s\n' "${report_boundary}"
  printf 'Final State: %s\n' "${report_final_state}"
  printf 'Topology: %s\n' "${report_topology_state}"
  printf 'Env: %s\n' "${report_env_state}"
  printf 'Guard: %s\n' "${report_guard_state}"
  printf 'Beads: %s\n' "${report_beads_state}"
  printf 'Beads Runtime: %s\n' "${report_beads_runtime_state}"
  if [[ -n "${report_beads_runtime_reason}" ]]; then
    printf 'Beads Runtime Reason: %s\n' "${report_beads_runtime_reason}"
  fi
  printf 'Handoff: %s\n' "${report_handoff_mode}"
  printf 'Approval Required: %s\n' "${report_approval_required}"
  if [[ "${report_requested_handoff_mode}" != "${report_handoff_mode}" ]]; then
    printf 'Requested Handoff: %s\n' "${report_requested_handoff_mode}"
  fi
  if [[ -n "${report_launch_command}" ]]; then
    printf 'Launch Command: %s\n' "${report_launch_command}"
  fi
  if [[ -n "${report_repair_command}" ]]; then
    printf 'Repair Command: %s\n' "${report_repair_command}"
  fi
  if [[ -n "${report_pending_work}" ]]; then
    printf 'Pending: %s\n' "${report_pending_work}"
  fi
  printf 'Next:\n'
  render_numbered_list "${report_next_steps[@]}"
  render_warning_list "${report_warnings[@]}"
  if [[ "${report_handoff_mode}" == "manual" ]]; then
    render_fenced_bash_block "${report_next_steps[@]}"
    render_phase_b_seed_prompt
    render_phase_b_seed_payload
  fi
}

render_finish_report() {
  if [[ "${output_format}" == "env" ]]; then
    render_env_kv "schema" "worktree-finish/v1"
    render_env_kv "phase" "${report_phase}"
    render_env_kv "boundary" "${report_boundary}"
    render_env_kv "final_state" "${report_final_state}"
    render_env_kv "worktree_action" "${report_worktree_action}"
    render_env_kv "worktree" "${report_worktree_path:-n/a}"
    render_env_kv "preview" "${report_path_preview:-n/a}"
    render_env_kv "branch" "${report_branch_name:-n/a}"
    render_env_kv "issue" "${report_issue_id:-n/a}"
    if [[ -n "${report_issue_title}" ]]; then
      render_env_kv "issue_title" "${report_issue_title}"
    fi
    render_env_kv "status" "${report_status}"
    render_env_kv "topology_state" "${report_topology_state}"
    render_env_kv "guard_state" "${report_guard_state}"
    render_env_kv "beads_state" "${report_beads_state}"
    render_env_kv "beads_runtime_state" "${report_beads_runtime_state}"
    if [[ -n "${report_beads_runtime_reason}" ]]; then
      render_env_kv "beads_runtime_reason" "${report_beads_runtime_reason}"
    fi
    render_env_kv "close_action" "${report_close_action}"
    if [[ -n "${report_close_command}" ]]; then
      render_env_kv "close_command" "${report_close_command}"
    fi
    if [[ -n "${report_repair_command}" ]]; then
      render_env_kv "repair_command" "${report_repair_command}"
    fi
    render_env_array "next" "${report_next_steps[@]}"
    render_env_array "warning" "${report_warnings[@]}"
    return 0
  fi

  printf 'Worktree: %s\n' "${report_worktree_path:-n/a}"
  printf 'Preview: %s\n' "${report_path_preview:-n/a}"
  printf 'Branch: %s\n' "${report_branch_name:-n/a}"
  printf 'Issue: %s\n' "${report_issue_id:-n/a}"
  if [[ -n "${report_issue_title}" ]]; then
    printf 'Issue Title: %s\n' "${report_issue_title}"
  fi
  printf 'Status: %s\n' "${report_status}"
  printf 'Phase: %s\n' "${report_phase}"
  printf 'Boundary: %s\n' "${report_boundary}"
  printf 'Final State: %s\n' "${report_final_state}"
  printf 'Topology: %s\n' "${report_topology_state}"
  printf 'Guard: %s\n' "${report_guard_state}"
  printf 'Beads: %s\n' "${report_beads_state}"
  printf 'Beads Runtime: %s\n' "${report_beads_runtime_state}"
  if [[ -n "${report_beads_runtime_reason}" ]]; then
    printf 'Beads Runtime Reason: %s\n' "${report_beads_runtime_reason}"
  fi
  printf 'Close: %s\n' "${report_close_command:-${report_close_action}}"
  if [[ -n "${report_repair_command}" ]]; then
    printf 'Repair Command: %s\n' "${report_repair_command}"
  fi
  printf 'Next:\n'
  render_numbered_list "${report_next_steps[@]}"
  render_warning_list "${report_warnings[@]}"
  render_fenced_bash_block "${report_next_steps[@]}"
}

render_cleanup_report() {
  if [[ "${output_format}" == "env" ]]; then
    render_env_kv "schema" "worktree-cleanup/v1"
    render_env_kv "phase" "${report_phase}"
    render_env_kv "boundary" "${report_boundary}"
    render_env_kv "final_state" "${report_final_state}"
    render_env_kv "worktree" "${report_worktree_path:-n/a}"
    render_env_kv "preview" "${report_path_preview:-n/a}"
    render_env_kv "branch" "${report_branch_name:-n/a}"
    render_env_kv "status" "${report_status}"
    render_env_kv "topology_state" "${report_topology_state}"
    render_env_kv "worktree_action" "${report_worktree_action}"
    render_env_kv "local_branch_action" "${report_local_branch_action}"
    render_env_kv "remote_branch_action" "${report_remote_branch_action}"
    render_env_kv "merge_check" "${report_merge_check}"
    if [[ -n "${report_default_branch_name}" ]]; then
      render_env_kv "default_branch" "${report_default_branch_name}"
    fi
    if [[ -n "${report_repair_command}" ]]; then
      render_env_kv "repair_command" "${report_repair_command}"
    fi
    render_env_array "next" "${report_next_steps[@]}"
    render_env_array "warning" "${report_warnings[@]}"
    return 0
  fi

  printf 'Worktree: %s\n' "${report_worktree_path:-n/a}"
  printf 'Preview: %s\n' "${report_path_preview:-n/a}"
  printf 'Branch: %s\n' "${report_branch_name:-n/a}"
  printf 'Status: %s\n' "${report_status}"
  printf 'Phase: %s\n' "${report_phase}"
  printf 'Boundary: %s\n' "${report_boundary}"
  printf 'Final State: %s\n' "${report_final_state}"
  printf 'Topology: %s\n' "${report_topology_state}"
  printf 'Worktree Action: %s\n' "${report_worktree_action}"
  printf 'Local Branch Action: %s\n' "${report_local_branch_action}"
  printf 'Remote Branch Action: %s\n' "${report_remote_branch_action}"
  printf 'Merge Check: %s\n' "${report_merge_check}"
  if [[ -n "${report_default_branch_name}" ]]; then
    printf 'Default Branch: %s\n' "${report_default_branch_name}"
  fi
  if [[ -n "${report_repair_command}" ]]; then
    printf 'Repair Command: %s\n' "${report_repair_command}"
  fi
  if [[ "${#report_next_steps[@]}" -gt 0 ]]; then
    printf 'Next:\n'
    render_numbered_list "${report_next_steps[@]}"
  fi
  render_warning_list "${report_warnings[@]}"
  if [[ "${#report_next_steps[@]}" -gt 0 ]]; then
    render_fenced_bash_block "${report_next_steps[@]}"
  fi
}

normalize_mode_inputs() {
  if [[ "${mode}" == "remove" ]]; then
    mode="cleanup"
  fi

  case "${output_format}" in
    human|env)
      ;;
    *)
      die "Unsupported output format: ${output_format}"
      ;;
  esac

  case "${handoff_profile}" in
    manual|terminal|codex)
      ;;
    *)
      die "Unsupported handoff profile: ${handoff_profile}"
      ;;
  esac

  case "${speckit_mode}" in
    true|false)
      ;;
    *)
      die "Unsupported speckit mode: ${speckit_mode}"
      ;;
  esac
}

render_context_summary() {
  debug "mode=${mode}"
  debug "branch=${branch:-<unset>}"
  debug "slug=${request_slug:-<unset>}"
  debug "issue=${issue_id:-<unset>}"
  debug "speckit=${speckit_mode}"
  debug "path=${target_path:-<unset>}"
  debug "repo=${repo_root:-<auto>}"
  debug "handoff=${handoff_profile}"
  debug "pending=${pending_summary:-<unset>}"
  debug "phase_b_seed_payload=${phase_b_seed_payload:+<set>}"
  debug "existing=${existing_branch:-<unset>}"
}

add_plan_next_step() {
  local step_text="$1"

  if [[ -n "${step_text}" ]]; then
    planning_next_steps+=("${step_text}")
  fi
}

add_plan_warning() {
  local warning_text="$1"

  if [[ -n "${warning_text}" ]]; then
    planning_warnings+=("${warning_text}")
  fi
}

set_planning_decision() {
  local exact_attached=""
  local exact_local=""
  local exact_remote=""
  local candidate=""
  local candidate_type=""
  local candidate_name=""
  local candidate_path=""
  local candidate_reason=""
  local similar_count=0

  planning_decision="create_clean"
  planning_question=""
  planning_next_steps=()

  for candidate in "${planning_candidates[@]}"; do
    IFS=$'\t' read -r candidate_type candidate_name candidate_path candidate_reason <<< "${candidate}"
    case "${candidate_reason}" in
      exact-attached-branch)
        exact_attached="${candidate}"
        ;;
      exact-local-branch)
        exact_local="${candidate}"
        ;;
      exact-remote-branch)
        exact_remote="${candidate}"
        ;;
      *)
        similar_count=$((similar_count + 1))
        ;;
    esac
  done

  if [[ -n "${exact_attached}" ]]; then
    IFS=$'\t' read -r candidate_type candidate_name candidate_path candidate_reason <<< "${exact_attached}"
    planning_decision="reuse_existing"
    planning_question="Existing worktree already uses the resolved branch. Reuse it instead of creating a duplicate."
    add_plan_next_step "Reuse the existing worktree at ${candidate_path}"
    if [[ "${topology_registry_state}" == "stale" ]]; then
      add_plan_next_step "Dispatch scripts/git-topology-registry.sh publish later if you need the tracked remote-governance snapshot updated"
    fi
    return 0
  fi

  if [[ -n "${exact_local}" ]]; then
    planning_decision="attach_existing_branch"
    planning_question="A local branch already exists for this request. Attach a worktree to it instead of creating another branch."
    add_plan_next_step "Create or attach a worktree for ${branch}"
    if [[ "${topology_registry_state}" == "stale" ]]; then
      add_plan_next_step "Keep working from live git state; dispatch scripts/git-topology-registry.sh publish later if the tracked remote-governance snapshot needs refresh"
    fi
    return 0
  fi

  if [[ -n "${exact_remote}" ]]; then
    planning_decision="needs_clarification"
    planning_question="A matching remote branch already exists on origin. Continue from that line or create a clean local branch?"
    add_plan_next_step "Ask one short question before mutating git state"
    add_plan_warning "Remote-only branch collision detected for ${branch}"
    return 0
  fi

  if [[ "${similar_count}" -gt 0 ]]; then
    planning_decision="needs_clarification"
    planning_question="Found similar branches/worktrees. Ask whether to create a clean worktree or continue one of the existing lines."
    add_plan_next_step "Ask one short clarification that includes the clean branch option ${branch}"
    return 0
  fi

  add_plan_next_step "Create a clean worktree on ${branch}"
  if [[ "${topology_registry_state}" == "stale" ]]; then
    add_plan_next_step "Do not auto-publish the topology snapshot from the invoking branch; dispatch scripts/git-topology-registry.sh publish later if you need the tracked remote-governance snapshot updated"
  fi
}

prepare_report_target() {
  reset_report
  set_report_target
  apply_discovery_to_report
  apply_guard_probe_to_report
  apply_branch_resolution_to_report
  apply_topology_probe_to_report
  apply_environment_probe_to_report
  discover_issue_context
}

select_handoff_mode() {
  reset_handoff_selection
  report_handoff_mode="manual"

  if [[ "${report_requested_handoff_mode}" == "manual" ]]; then
    return 0
  fi

  if [[ ! "$(uname -s)" == "Darwin" ]]; then
    handoff_support_state="unsupported"
    handoff_fallback_reason="Automatic handoff is only implemented for macOS Terminal.app."
    add_warning "${handoff_fallback_reason}"
    return 0
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    handoff_support_state="unsupported"
    handoff_fallback_reason="Automatic handoff requires osascript on macOS."
    add_warning "${handoff_fallback_reason}"
    return 0
  fi

  case "${report_requested_handoff_mode}" in
    terminal)
      case "${report_status}" in
        ready_for_codex|needs_env_approval|created)
          report_handoff_mode="terminal"
          handoff_support_state="available"
          ;;
        *)
          handoff_support_state="unsupported"
          handoff_fallback_reason="Terminal handoff is only available once the worktree has a usable target path."
          add_warning "${handoff_fallback_reason}"
          ;;
      esac
      ;;
    codex)
      if ! command -v codex >/dev/null 2>&1; then
        handoff_support_state="unsupported"
        handoff_fallback_reason="Codex handoff requires the codex CLI to be installed."
        add_warning "${handoff_fallback_reason}"
      elif [[ "${report_status}" == "ready_for_codex" ]]; then
        report_handoff_mode="codex"
        handoff_support_state="available"
      else
        handoff_support_state="unsupported"
        handoff_fallback_reason="Codex handoff requires status ready_for_codex."
        add_warning "${handoff_fallback_reason}"
      fi
      ;;
  esac
}

apple_script_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

build_terminal_session_command() {
  local plain_bd_bootstrap=""

  case "${report_handoff_mode}" in
    terminal)
      printf 'cd %s\n' "$(shell_quote "${report_worktree_path}")"
      if plain_bd_bootstrap="$(build_plain_bd_bootstrap_command_for_path "${report_worktree_path}")"; then
        printf '%s\n' "${plain_bd_bootstrap}"
      fi
      ;;
    codex)
      printf 'cd %s\n' "$(shell_quote "${report_worktree_path}")"
      if plain_bd_bootstrap="$(build_plain_bd_bootstrap_command_for_path "${report_worktree_path}")"; then
        printf '%s\n' "${plain_bd_bootstrap}"
      fi
      printf 'codex\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

build_terminal_automation_command() {
  local session_command="$1"
  local escaped_command=""

  escaped_command="$(apple_script_escape "${session_command}")"
  printf 'osascript -e '\''tell application "Terminal" to activate'\'' -e '\''tell application "Terminal" to do script "%s"'\''\n' "${escaped_command}"
}

launch_terminal_handoff() {
  local session_command="$1"
  local escaped_command=""

  escaped_command="$(apple_script_escape "${session_command}")"
  osascript \
    -e 'tell application "Terminal" to activate' \
    -e "tell application \"Terminal\" to do script \"${escaped_command}\""
}

apply_selected_handoff() {
  local session_command=""
  local exit_code=0

  if [[ "${report_handoff_mode}" == "manual" ]]; then
    return 0
  fi

  session_command="$(build_terminal_session_command)"
  handoff_launch_command="$(build_terminal_automation_command "${session_command}")"

  if [[ "${WORKTREE_READY_DRY_RUN:-0}" == "1" ]]; then
    report_next_steps=()
    add_next_step "${handoff_launch_command}"
    add_warning "Dry-run mode enabled; handoff command was not executed."
    return 0
  fi

  set +e
  launch_terminal_handoff "${session_command}"
  exit_code=$?
  set -e

  if [[ "${exit_code}" -ne 0 ]]; then
    report_handoff_mode="manual"
    add_warning "Automatic ${report_requested_handoff_mode} handoff failed. Falling back to manual steps."
    add_warning "Launch command: ${handoff_launch_command}"
    return 0
  fi

  report_next_steps=()
  case "${report_handoff_mode}" in
    terminal)
      add_next_step "Terminal.app opened at ${report_worktree_path}"
      case "${report_status}" in
        needs_env_approval)
          add_next_step "Run direnv allow in the new terminal"
          add_next_step "Launch codex when the environment is ready"
          ;;
        created)
          add_next_step "If direnv prompts in the new terminal, approve the environment before launching codex"
          ;;
      esac
      ;;
    codex)
      add_next_step "Codex launch requested in a new Terminal.app tab at ${report_worktree_path}"
      ;;
  esac
}

render_mode_placeholder() {
  local mode_name="$1"

  prepare_report_target
  set_readiness_status
  select_handoff_mode
  set_readiness_next_steps "${mode_name}"
  apply_selected_handoff
  set_handoff_contract "${mode_name}"

  if [[ "${report_env_state}" == "unknown" ]]; then
    add_warning "Environment readiness has not been probed yet."
  fi

  render_readiness_report
  set_command_exit_code_from_readiness
}

render_doctor_report() {
  prepare_report_target
  set_doctor_status
  report_handoff_mode="manual"
  set_doctor_next_steps
  set_handoff_contract "doctor"
  render_readiness_report
  set_command_exit_code_from_readiness
}

render_finish_contract_report() {
  prepare_report_target
  set_finish_status
  set_finish_next_steps
  set_finish_contract
  render_finish_report
  set_command_exit_code_from_readiness
}

render_cleanup_contract_report() {
  prepare_report_target
  if [[ "${resolved_repo_root}" != "${resolved_canonical_root}" ]]; then
    local delete_flag=""
    local cleanup_args="--branch <branch>"

    if [[ "${delete_branch_requested}" == "true" ]]; then
      delete_flag=" --delete-branch"
    fi
    if [[ -n "${branch}" ]]; then
      cleanup_args="--branch $(shell_quote "${branch}")"
    elif [[ -n "${target_path}" ]]; then
      cleanup_args="--path $(shell_quote "${target_path}")"
    fi

    report_phase="cleanup"
    report_boundary="none"
    report_status="cleanup_blocked"
    report_final_state="cleanup_blocked"
    report_worktree_action="blocked"
    report_repair_command="cd $(shell_quote "${resolved_canonical_root}") && scripts/worktree-ready.sh cleanup ${cleanup_args}${delete_flag}"
    add_warning "Cleanup must run from the canonical root worktree."
    add_next_step "cd $(shell_quote "${resolved_canonical_root}")"
    if [[ -n "${branch}" ]]; then
      add_next_step "scripts/worktree-ready.sh cleanup --branch $(shell_quote "${branch}")${delete_flag}"
    elif [[ -n "${target_path}" ]]; then
      add_next_step "scripts/worktree-ready.sh cleanup --path $(shell_quote "${target_path}")${delete_flag}"
    fi
    render_cleanup_report
    set_command_exit_code_from_cleanup
    return 0
  fi

  if cleanup_target_arguments_conflict; then
    report_phase="cleanup"
    report_boundary="none"
    report_status="cleanup_blocked"
    report_final_state="cleanup_blocked"
    report_worktree_action="blocked"
    add_warning "Cleanup arguments conflict: --path $(shell_quote "${target_path}") resolves to branch '${discovered_branch_name:-unknown}', not requested branch '${branch}'."
    add_next_step "Retry cleanup with --path $(shell_quote "${target_path}") only"
    if [[ -n "${discovered_branch_name}" ]]; then
      add_next_step "Retry cleanup with --branch $(shell_quote "${discovered_branch_name}") only"
    fi
    render_cleanup_report
    set_command_exit_code_from_cleanup
    return 0
  fi

  execute_cleanup_worktree_action || true
  if [[ "${report_worktree_action}" != "blocked" && "${report_cleanup_reconcile_required}" != "true" ]]; then
    execute_cleanup_branch_actions || true
  fi
  set_cleanup_contract
  render_cleanup_report
  set_command_exit_code_from_cleanup
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

  discover_topology_registry_state
  discover_target_state
  discover_beads_runtime_state
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

  discover_topology_registry_state
  discover_target_state
  discover_beads_runtime_state
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

  discover_topology_registry_state
  discover_target_state
  discover_beads_runtime_state
  discover_guard_state
  discover_environment_state
}

prepare_finish_context() {
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

  discover_topology_registry_state
  discover_target_state
  discover_beads_runtime_state
  discover_guard_state
  discover_environment_state
}

prepare_cleanup_context() {
  require_git_repo
  branch_resolution_state="not_required"

  if [[ -z "${branch}" && -z "${target_path}" ]]; then
    die "cleanup mode requires --branch or --path"
  fi

  if [[ -n "${branch}" ]]; then
    resolve_existing_branch_state || true
  fi

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  elif [[ -n "${branch}" ]]; then
    derive_sibling_worktree_path "${branch}"
  fi

  discover_topology_registry_state
  discover_target_state
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

  discover_topology_registry_state
  discover_target_state
  discover_beads_runtime_state
  discover_guard_state
  discover_environment_state
}

prepare_plan_context() {
  local resolved_slug=""

  require_git_repo
  reset_plan_state
  branch_resolution_state="not_required"

  if [[ -z "${request_slug}" && -n "${branch}" ]]; then
    request_slug="$(strip_common_branch_prefix "${branch}")"
  fi

  if [[ -z "${request_slug}" && -n "${existing_branch}" ]]; then
    request_slug="$(strip_common_branch_prefix "${existing_branch}")"
  fi

  if [[ -z "${request_slug}" ]]; then
    die "plan mode requires --slug, --branch, or --existing"
  fi

  resolved_slug="$(derive_effective_slug)"
  branch="$(derive_branch_from_request)"

  if [[ -n "${target_path}" ]]; then
    resolve_explicit_path "${target_path}"
  elif issue_requests_speckit; then
    derive_sibling_worktree_path "${branch}"
  else
    derive_request_worktree_path
  fi

  discover_topology_registry_state
  discover_target_state
  discover_similar_targets "${resolved_slug}" "${branch}"

  if [[ "${topology_registry_state}" == "stale" ]]; then
    add_plan_warning "Git topology registry is stale; plan results were derived from live git state."
  fi

  set_planning_decision
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
  render_doctor_report
}

handle_finish() {
  prepare_finish_context
  render_finish_contract_report
}

handle_cleanup() {
  prepare_cleanup_context
  render_cleanup_contract_report
}

handle_handoff() {
  prepare_handoff_context
  render_mode_placeholder "handoff"
}

handle_plan() {
  prepare_plan_context
  render_plan_report
  set_command_exit_code_from_plan
}

main() {
  parse_args "$@"
  normalize_mode_inputs
  render_context_summary

  case "${mode}" in
    plan)
      handle_plan
      ;;
    create)
      handle_create
      ;;
    attach)
      handle_attach
      ;;
    doctor)
      handle_doctor
      ;;
    finish)
      handle_finish
      ;;
    cleanup)
      handle_cleanup
      ;;
    handoff)
      handle_handoff
      ;;
    *)
      die "Unknown mode: ${mode}"
      ;;
  esac

  exit "${command_exit_code}"
}

main "$@"
