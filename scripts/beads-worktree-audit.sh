#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/beads-resolve-db.sh
source "${REPO_ROOT}/scripts/beads-resolve-db.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/beads-worktree-audit.sh [--repo <path>] [--format <human|env>] [--apply-safe] [--bootstrap-source <ref>]

Description:
  Audit Beads ownership across the live git worktree set for the current
  repository. In the canonical root, fail closed when sibling worktrees still
  carry legacy .beads/redirect residue or otherwise cannot guarantee local
  ownership safely.

  --apply-safe localizes recoverable sibling worktrees in place. When older
  branches are missing the plain-bd foundation entirely, bootstrap imports can
  be pulled from --bootstrap-source (default: origin/main).
EOF
}

die() {
  echo "[beads-worktree-audit] $*" >&2
  exit 2
}

repo_override=""
output_format="human"
apply_safe="false"
bootstrap_source="origin/main"

report_mode=""
report_repo_root=""
report_canonical_root=""
report_current_root=""
report_problem_count=0
report_warning_count=0
report_action_count=0

declare -a REPORT_LINES=()
declare -a NEXT_STEPS=()
declare -a LINKED_BRANCHES=()

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo_override="${2:-}"
        [[ -n "${repo_override}" ]] || die "--repo requires a value"
        shift 2
        ;;
      --format)
        output_format="${2:-}"
        [[ -n "${output_format}" ]] || die "--format requires a value"
        shift 2
        ;;
      --apply-safe)
        apply_safe="true"
        shift
        ;;
      --bootstrap-source)
        bootstrap_source="${2:-}"
        [[ -n "${bootstrap_source}" ]] || die "--bootstrap-source requires a value"
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

  case "${output_format}" in
    human|env) ;;
    *)
      die "Unsupported output format: ${output_format}"
      ;;
  esac
}

add_report_line() {
  REPORT_LINES+=("$1")
}

add_next_step() {
  NEXT_STEPS+=("$1")
}

default_branch_name() {
  local default_branch=""

  default_branch="$(git -C "${report_repo_root}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  default_branch="${default_branch#origin/}"
  if [[ -n "${default_branch}" ]]; then
    printf '%s\n' "${default_branch}"
    return 0
  fi

  printf 'main\n'
}

classify_worktree_state() {
  local worktree_path="$1"
  local beads_dir="${worktree_path}/.beads"
  local config_path="${beads_dir}/config.yaml"
  local issues_path="${beads_dir}/issues.jsonl"
  local redirect_path="${beads_dir}/redirect"
  local has_local_runtime="false"
  local has_runtime_shell="false"

  if beads_resolve_has_local_runtime "${beads_dir}"; then
    has_local_runtime="true"
  fi

  if beads_resolve_has_runtime_shell "${beads_dir}"; then
    has_runtime_shell="true"
  fi

  if [[ -f "${redirect_path}" ]]; then
    if [[ -f "${config_path}" && -f "${issues_path}" ]]; then
      printf '%s\n' "migratable_legacy"
      return 0
    fi
    printf '%s\n' "damaged_blocked"
    return 0
  fi

  if [[ -f "${config_path}" && -f "${issues_path}" && "${has_local_runtime}" == "true" ]]; then
    printf '%s\n' "current"
    return 0
  fi

  if [[ -f "${config_path}" && "${has_local_runtime}" == "true" && ! -f "${issues_path}" ]]; then
    printf '%s\n' "post_migration_runtime_only"
    return 0
  fi

  if [[ -f "${config_path}" && ! -f "${issues_path}" ]]; then
    printf '%s\n' "runtime_bootstrap_required"
    return 0
  fi

  if [[ -f "${config_path}" && -f "${issues_path}" ]]; then
    if [[ "${has_runtime_shell}" == "true" ]]; then
      printf '%s\n' "runtime_bootstrap_required"
      return 0
    fi

    printf '%s\n' "partial_foundation"
    return 0
  fi

  if [[ -d "${beads_dir}" ]]; then
    printf '%s\n' "missing_foundation"
    return 0
  fi

  printf '%s\n' "no_beads"
}

collect_worktrees() {
  local repo_root="$1"

  git -C "${repo_root}" worktree list --porcelain | awk '
    /^worktree / {
      if (path != "") {
        print path
      }
      path = substr($0, 10)
      next
    }
    END {
      if (path != "") {
        print path
      }
    }
  '
}

collect_worktree_branches() {
  local repo_root="$1"
  local line=""
  local current_branch=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        if [[ -n "${current_branch}" ]]; then
          printf '%s\n' "${current_branch}"
        fi
        ;;
    esac
  done < <(git -C "${repo_root}" worktree list --porcelain)
}

audit_worktree() {
  local worktree_path="$1"
  local issues_path="${worktree_path}/.beads/issues.jsonl"
  local state=""
  local action="none"
  local severity="ok"
  local helper_command=""

  state="$(classify_worktree_state "${worktree_path}")"
  helper_command="./scripts/beads-worktree-localize.sh --path $(printf '%q' "${worktree_path}")"
  if [[ -n "${bootstrap_source}" ]]; then
    helper_command+=" --bootstrap-source $(printf '%q' "${bootstrap_source}")"
  fi

  if [[ "${state}" == "runtime_bootstrap_required" && ! -f "${issues_path}" ]]; then
    helper_command="cd $(printf '%q' "${worktree_path}") && /usr/local/bin/bd doctor --json && ./scripts/beads-worktree-localize.sh --path ."
  fi

  if [[ "${apply_safe}" == "true" ]]; then
    case "${state}" in
      migratable_legacy|partial_foundation|damaged_blocked|missing_foundation)
        "${SCRIPT_DIR}/beads-worktree-localize.sh" --path "${worktree_path}" --bootstrap-source "${bootstrap_source}" >/dev/null
        state="$(classify_worktree_state "${worktree_path}")"
        action="localized"
        ((report_action_count += 1))
        ;;
    esac
  fi

  case "${state}" in
    current|no_beads|post_migration_runtime_only)
      severity="ok"
      ;;
    partial_foundation|runtime_bootstrap_required)
      severity="warn"
      if [[ "${action}" == "none" ]]; then
        if [[ "${state}" == "runtime_bootstrap_required" ]]; then
          action="runtime_repair"
        else
          action="localize_safe"
        fi
      fi
      add_next_step "${helper_command}"
      ;;
    migratable_legacy)
      severity="problem"
      if [[ "${action}" == "none" ]]; then
        action="localize_safe"
      fi
      add_next_step "${helper_command}"
      ;;
    damaged_blocked|missing_foundation)
      severity="problem"
      if [[ "${action}" == "none" ]]; then
        action="manual_recovery"
      fi
      add_next_step "${helper_command}"
      ;;
    *)
      severity="problem"
      if [[ "${action}" == "none" ]]; then
        action="manual_recovery"
      fi
      add_next_step "${helper_command}"
      ;;
  esac

  case "${severity}" in
    warn)
      ((report_warning_count += 1))
      ;;
    problem)
      ((report_problem_count += 1))
      ;;
  esac

  add_report_line "worktree|${severity}|${state}|${action}|${worktree_path}"
}

branch_has_linked_worktree() {
  local branch_name="$1"
  local linked_branch=""

  for linked_branch in "${LINKED_BRANCHES[@]+"${LINKED_BRANCHES[@]}"}"; do
    if [[ "${linked_branch}" == "${branch_name}" ]]; then
      return 0
    fi
  done

  return 1
}

audit_branch_only_local() {
  local branch_name="$1"
  local default_branch="$2"
  local state="branch_only_active"
  local action="review_branch_owner"

  if [[ -z "${branch_name}" || "${branch_name}" == "${default_branch}" || "${branch_name}" == "chore/topology-registry-publish" ]]; then
    return 0
  fi

  if branch_has_linked_worktree "${branch_name}"; then
    return 0
  fi

  if git -C "${report_repo_root}" merge-base --is-ancestor "refs/heads/${branch_name}" "refs/heads/${default_branch}" >/dev/null 2>&1; then
    state="branch_only_merged"
    action="delete_local_branch_if_stale"
    add_next_step "git -C $(printf '%q' "${report_repo_root}") branch -d $(printf '%q' "${branch_name}")"
  else
    add_next_step "git -C $(printf '%q' "${report_repo_root}") log --oneline --decorate -n 20 $(printf '%q' "${branch_name}") --"
  fi

  ((report_warning_count += 1))
  add_report_line "branch|warn|${state}|${action}|${branch_name}"
}

render_human() {
  printf 'Mode: %s\n' "${report_mode}"
  printf 'Repo Root: %s\n' "${report_repo_root}"
  printf 'Canonical Root: %s\n' "${report_canonical_root}"
  if [[ "${report_mode}" == "canonical_root" ]]; then
    printf 'Problems: %s\n' "${report_problem_count}"
    printf 'Warnings: %s\n' "${report_warning_count}"
    printf 'Actions: %s\n' "${report_action_count}"
    printf '\n'
    for line in "${REPORT_LINES[@]}"; do
      IFS='|' read -r scope severity state action subject <<< "${line}"
      if [[ "${scope}" == "branch" ]]; then
        printf '[%s] scope=branch state=%s action=%s branch=%s\n' "${severity}" "${state}" "${action}" "${subject}"
      else
        printf '[%s] state=%s action=%s path=%s\n' "${severity}" "${state}" "${action}" "${subject}"
      fi
    done
    if [[ "${#NEXT_STEPS[@]}" -gt 0 ]]; then
      printf '\nNext Steps:\n'
      printf '%s\n' "${NEXT_STEPS[@]}" | awk '!seen[$0]++ {print "  - " $0}'
    fi
  else
    printf 'Message: Non-canonical worktree; sibling ownership audit is informational only here.\n'
  fi
}

render_env() {
  printf 'schema=%q\n' "beads-worktree-audit/v1"
  printf 'mode=%q\n' "${report_mode}"
  printf 'repo_root=%q\n' "${report_repo_root}"
  printf 'canonical_root=%q\n' "${report_canonical_root}"
  printf 'current_root=%q\n' "${report_current_root}"
  printf 'problem_count=%q\n' "${report_problem_count}"
  printf 'warning_count=%q\n' "${report_warning_count}"
  printf 'action_count=%q\n' "${report_action_count}"
}

main() {
  local repo_root=""
  local canonical_root=""
  local worktree_path=""

  parse_args "$@"

  if [[ -n "${repo_override}" ]]; then
    repo_root="$(beads_resolve_repo_root "${repo_override}")"
  else
    repo_root="$(beads_resolve_repo_root "$PWD")"
  fi

  [[ -n "${repo_root}" ]] || die "Unable to resolve repository root"

  canonical_root="$(beads_resolve_canonical_root "${repo_root}")"
  [[ -n "${canonical_root}" ]] || die "Unable to resolve canonical root"

  report_repo_root="${repo_root}"
  report_canonical_root="${canonical_root}"
  report_current_root="${repo_root}"

  if [[ "${repo_root}" != "${canonical_root}" ]]; then
    report_mode="non_canonical"
    if [[ "${output_format}" == "env" ]]; then
      render_env
    else
      render_human
    fi
    exit 0
  fi

  report_mode="canonical_root"
  LINKED_BRANCHES=()
  while IFS= read -r linked_branch; do
    [[ -n "${linked_branch}" ]] || continue
    LINKED_BRANCHES+=("${linked_branch}")
  done < <(collect_worktree_branches "${repo_root}")

  while IFS= read -r worktree_path; do
    [[ -n "${worktree_path}" ]] || continue
    if [[ "${worktree_path}" == "${canonical_root}" ]]; then
      continue
    fi
    audit_worktree "${worktree_path}"
  done < <(collect_worktrees "${repo_root}")

  while IFS= read -r branch_name; do
    [[ -n "${branch_name}" ]] || continue
    audit_branch_only_local "${branch_name}" "$(default_branch_name)"
  done < <(git -C "${repo_root}" for-each-ref --format='%(refname:short)' refs/heads)

  if [[ "${output_format}" == "env" ]]; then
    render_env
  else
    render_human
  fi

  if [[ "${report_problem_count}" -gt 0 ]]; then
    exit 23
  fi

  exit 0
}

main "$@"
