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

classify_worktree_state() {
  local worktree_path="$1"
  local beads_dir="${worktree_path}/.beads"
  local config_path="${beads_dir}/config.yaml"
  local issues_path="${beads_dir}/issues.jsonl"
  local redirect_path="${beads_dir}/redirect"
  local has_local_runtime="false"

  if beads_resolve_has_local_runtime "${beads_dir}"; then
    has_local_runtime="true"
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

  if [[ -f "${config_path}" && -f "${issues_path}" ]]; then
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

audit_worktree() {
  local worktree_path="$1"
  local state=""
  local action="none"
  local severity="ok"
  local helper_command=""

  state="$(classify_worktree_state "${worktree_path}")"
  helper_command="./scripts/beads-worktree-localize.sh --path $(printf '%q' "${worktree_path}")"
  if [[ -n "${bootstrap_source}" ]]; then
    helper_command+=" --bootstrap-source $(printf '%q' "${bootstrap_source}")"
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
    partial_foundation)
      severity="warn"
      if [[ "${action}" == "none" ]]; then
        action="localize_safe"
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

  add_report_line "${severity}|${state}|${action}|${worktree_path}"
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
      IFS='|' read -r severity state action path <<< "${line}"
      printf '[%s] state=%s action=%s path=%s\n' "${severity}" "${state}" "${action}" "${path}"
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

  while IFS= read -r worktree_path; do
    [[ -n "${worktree_path}" ]] || continue
    if [[ "${worktree_path}" == "${canonical_root}" ]]; then
      continue
    fi
    audit_worktree "${worktree_path}"
  done < <(collect_worktrees "${repo_root}")

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
