#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/beads-resolve-db.sh
source "${REPO_ROOT}/scripts/beads-resolve-db.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/beads-worktree-localize.sh [--path <worktree>] [--format <human|env>] [--check] [--bootstrap-source <ref>]

Description:
  Localize Beads ownership for an existing git worktree by removing legacy
  redirect residue and materializing a worktree-local Beads runtime from the
  local foundation when that is safe to do. For older worktrees that still
  lack the plain-bd foundation, `--bootstrap-source` can import the tracked
  recovery files before localization. For runtime-only drift after JSONL
  retirement, the same helper can quarantine a stale Dolt shell, rerun
  `bd bootstrap`, and import the newest compatibility JSONL backup when one
  is available. It must never restore tracked `.beads/issues.jsonl`.
EOF
}

die() {
  echo "[beads-worktree-localize] $*" >&2
  exit 2
}

target_path=""
output_format="human"
check_only="false"
bootstrap_source=""

report_state=""
report_action=""
report_worktree=""
report_db_path=""
report_message=""
report_notice=""
report_bootstrap_source=""
report_runtime_repair_mode=""

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

detect_active_migration_mode() {
  local pilot_mode_file="${target_path}/.beads/pilot-mode.json"
  local cutover_mode_file="${target_path}/.beads/cutover-mode.json"

  if [[ -f "${cutover_mode_file}" ]]; then
    printf 'cutover\n'
    return 0
  fi

  if [[ -f "${pilot_mode_file}" ]]; then
    printf 'pilot\n'
    return 0
  fi

  return 1
}

classify_state() {
  local beads_dir="${target_path}/.beads"
  local config_path="${beads_dir}/config.yaml"
  local issues_path="${beads_dir}/issues.jsonl"
  local db_path="${beads_dir}/beads.db"
  local dolt_path="${beads_dir}/dolt"
  local redirect_path="${beads_dir}/redirect"
  local active_migration_mode=""
  local has_local_runtime="false"
  local has_runtime_shell="false"
  local runtime_probe_state="not_run"

  report_db_path="${db_path}"
  report_notice=""
  report_bootstrap_source=""
  report_runtime_repair_mode=""

  if beads_resolve_has_local_runtime "${beads_dir}"; then
    has_local_runtime="true"
    if [[ ! -e "${db_path}" && -d "${dolt_path}" ]]; then
      report_db_path="${dolt_path}"
    fi
  fi
  if beads_resolve_has_runtime_shell "${beads_dir}"; then
    has_runtime_shell="true"
    if [[ "${has_local_runtime}" != "true" && -d "${dolt_path}" ]]; then
      report_db_path="${dolt_path}"
    fi
  fi
  if [[ "${has_local_runtime}" == "true" ]]; then
    beads_resolve_probe_local_runtime_health "${target_path}" || true
    runtime_probe_state="${BEADS_RESOLVE_RUNTIME_PROBE_STATE:-not_run}"
  fi

  active_migration_mode="$(detect_active_migration_mode 2>/dev/null || true)"
  if [[ -n "${active_migration_mode}" ]]; then
    report_state="${active_migration_mode}_mode_active"
    report_action="stop_and_report"
    if [[ "${active_migration_mode}" == "cutover" ]]; then
      report_message="Cutover mode is already active for this worktree; the localization helper is a retired compatibility path."
      report_notice="Use ./scripts/beads-dolt-rollout.sh verify --worktree . for the active cutover review surface."
    else
      report_message="Pilot mode is already active for this worktree; the localization helper is a retired compatibility path."
      report_notice="Use ./scripts/beads-dolt-pilot.sh review for the active pilot review surface."
    fi
    return 0
  fi

  if [[ -f "${redirect_path}" ]]; then
    if [[ -f "${config_path}" && -f "${issues_path}" ]]; then
      report_state="migratable_legacy"
      report_action="localize_in_place"
      report_message="Legacy redirect metadata is present, but local foundation files are available for safe in-place localization."
      report_notice="Residual canonical-root cleanup remains a separate follow-up."
      return 0
    fi

    if [[ -n "${bootstrap_source}" ]]; then
      report_state="bootstrap_required"
      report_action="bootstrap_and_localize"
      report_message="Legacy redirect metadata is present and local Beads foundation is incomplete; bootstrap files must be imported before safe localization."
      report_notice="Bootstrap imports only the plain-bd recovery foundation from the requested source ref."
      report_bootstrap_source="${bootstrap_source}"
      return 0
    fi

    report_state="damaged_blocked"
    report_action="stop_and_report"
    report_message="Legacy redirect metadata is present, but local Beads foundation files are incomplete."
    report_notice="Do not fall back to the canonical root tracker."
    return 0
  fi

  if [[ -f "${config_path}" && -f "${issues_path}" && "${has_local_runtime}" == "true" && "${runtime_probe_state}" != "unhealthy" ]]; then
    report_state="current"
    report_action="none"
    report_message="This worktree already has localized Beads ownership."
    return 0
  fi

  if [[ -f "${config_path}" && "${has_local_runtime}" == "true" && "${runtime_probe_state}" != "unhealthy" && ! -f "${issues_path}" ]]; then
    report_state="post_migration_runtime_only"
    report_action="none"
    report_message="Tracked .beads/issues.jsonl is already retired for this worktree; use the local Beads runtime as the backlog source of truth."
    report_notice="If plain bd cannot read the local backlog, treat that as a local Beads repair problem and run /usr/local/bin/bd doctor --json before any repair step."
    return 0
  fi

  if [[ -f "${config_path}" && ! -f "${issues_path}" ]]; then
    report_state="runtime_bootstrap_required"
    report_action="stop_and_report"
    report_runtime_repair_mode="repair_runtime_only"
    report_message="Tracked .beads/issues.jsonl is already retired for this worktree, but the local Dolt-backed Beads runtime is incomplete."
    report_notice="Run /usr/local/bin/bd doctor --json first, then ./scripts/beads-worktree-localize.sh --path . to quarantine any stale runtime shell, rerun bootstrap, and import the newest compatibility backup when available. Do not restore tracked JSONL."
    return 0
  fi

  if [[ -f "${config_path}" && -f "${issues_path}" ]]; then
    if [[ "${runtime_probe_state}" == "unhealthy" || "${has_runtime_shell}" == "true" ]]; then
      report_state="runtime_bootstrap_required"
      report_action="stop_and_report"
      report_runtime_repair_mode="rebuild_local_foundation"
      if [[ "${runtime_probe_state}" == "unhealthy" ]]; then
        report_message="A local named 'beads' database exists on disk, but plain bd cannot read it safely yet."
      else
        report_message="A local Dolt-backed Beads runtime shell exists, but the named 'beads' database is not materialized yet."
      fi
      report_notice="Run ./scripts/beads-worktree-localize.sh --path . to quarantine the partial runtime, bootstrap a fresh named DB, and reimport the tracked local backlog."
      return 0
    fi

    report_state="partial_foundation"
    report_action="rebuild_local_foundation"
    report_message="Local Beads foundation exists, but the local Beads runtime must be materialized in place."
    return 0
  fi

  if [[ -n "${bootstrap_source}" ]]; then
    report_state="bootstrap_required"
    report_action="bootstrap_and_localize"
    report_message="This worktree does not have enough local Beads foundation files; bootstrap imports are required before safe localization."
    report_notice="Bootstrap imports only the plain-bd recovery foundation from the requested source ref."
    report_bootstrap_source="${bootstrap_source}"
    return 0
  fi

  report_state="damaged_blocked"
  report_action="stop_and_report"
  report_message="This worktree does not have enough local Beads foundation files to localize ownership safely."
}

bootstrap_foundation() {
  local -a bootstrap_files=(
    ".beads/config.yaml"
    ".beads/issues.jsonl"
    "bin/bd"
    "scripts/beads-resolve-db.sh"
    "scripts/beads-worktree-localize.sh"
    ".envrc"
  )

  [[ -n "${bootstrap_source}" ]] || die "bootstrap_foundation requires --bootstrap-source"

  (
    cd "${target_path}"
    git checkout "${bootstrap_source}" -- "${bootstrap_files[@]}"
  )
}

find_runtime_import_source() {
  local beads_dir="$1"
  local latest=""
  local candidate=""
  local search_dir=""

  for search_dir in "${beads_dir}/backup" "${beads_dir}/legacy-jsonl-backup"; do
    [[ -d "${search_dir}" ]] || continue
    while IFS= read -r candidate; do
      if [[ -z "${latest}" || "${candidate}" -nt "${latest}" ]]; then
        latest="${candidate}"
      fi
    done < <(find "${search_dir}" -maxdepth 1 -type f -name '*.jsonl' -print 2>/dev/null)
    if [[ -n "${latest}" ]]; then
      printf '%s\n' "${latest}"
      return 0
    fi
  done

  return 1
}

materialize_local_db() {
  local import_source="${1:-}"
  local system_bd="${BEADS_SYSTEM_BD:-}"
  local beads_dir="${target_path}/.beads"
  local db_path="${beads_dir}/beads.db"
  local dolt_path="${beads_dir}/dolt"
  local recovery_dir="${beads_dir}/recovery"
  local recovery_path=""
  local timestamp=""
  local artifact=""
  local import_db_path=""
  local runtime_probe_state="not_run"
  local -a stale_runtime_artifacts=(
    "metadata.json"
    "interactions.jsonl"
    "dolt-server.lock"
    "dolt-server.log"
    "dolt-server.pid"
    "dolt-server.port"
  )

  if [[ -z "${system_bd}" ]]; then
    system_bd="$(beads_resolve_find_system_bd "${REPO_ROOT}/bin/bd")" || die "Could not locate the system bd binary"
  fi

  if beads_resolve_has_local_runtime "${beads_dir}"; then
    beads_resolve_probe_local_runtime_health "${target_path}" || true
    runtime_probe_state="${BEADS_RESOLVE_RUNTIME_PROBE_STATE:-not_run}"
  fi

  if [[ "${runtime_probe_state}" == "unhealthy" ]] || \
     ([[ ! -d "${dolt_path}/beads" && ! -d "${dolt_path}/beads/.dolt" ]] && \
      [[ -d "${dolt_path}" || -e "${beads_dir}/metadata.json" || -e "${beads_dir}/interactions.jsonl" ]]); then
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    recovery_path="${recovery_dir}/runtime-pre-init-${timestamp}"
    mkdir -p "${recovery_path}"
    if [[ -d "${dolt_path}" ]]; then
      mv "${dolt_path}" "${recovery_path}/dolt"
    fi
    for artifact in "${stale_runtime_artifacts[@]}"; do
      if [[ -e "${beads_dir}/${artifact}" ]]; then
        mv "${beads_dir}/${artifact}" "${recovery_path}/${artifact}"
      fi
    done
  fi

  (
    cd "${target_path}"
    "${system_bd}" bootstrap >/dev/null 2>&1
  )

  if [[ -n "${import_source}" ]]; then
    if [[ -d "${dolt_path}" ]]; then
      import_db_path="${dolt_path}"
    else
      import_db_path="${db_path}"
    fi
    (
      cd "${target_path}"
      "${system_bd}" --db "${import_db_path}" import "${import_source}" >/dev/null 2>&1
    )
  fi
}

localize_state() {
  local redirect_path="${target_path}/.beads/redirect"
  local bootstrap_source_used=""

  case "${report_state}" in
    current)
      return 0
      ;;
    post_migration_runtime_only)
      return 0
      ;;
    runtime_bootstrap_required)
      case "${report_runtime_repair_mode}" in
        rebuild_local_foundation)
          materialize_local_db "${target_path}/.beads/issues.jsonl"
          ;;
        repair_runtime_only)
          materialize_local_db "$(find_runtime_import_source "${target_path}/.beads" 2>/dev/null || true)"
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    migratable_legacy)
      rm -f "${redirect_path}"
      materialize_local_db "${target_path}/.beads/issues.jsonl"
      ;;
    bootstrap_required)
      bootstrap_source_used="${report_bootstrap_source}"
      bootstrap_foundation
      rm -f "${redirect_path}"
      materialize_local_db "${target_path}/.beads/issues.jsonl"
      ;;
    partial_foundation)
      materialize_local_db "${target_path}/.beads/issues.jsonl"
      ;;
    damaged_blocked)
      return 1
      ;;
    *)
      die "Unsupported localization state: ${report_state}"
      ;;
  esac

  classify_state
  if [[ -n "${bootstrap_source_used}" ]]; then
    report_bootstrap_source="${bootstrap_source_used}"
  fi
}

render_env() {
  printf 'schema=%q\n' "beads-localize/v1"
  printf 'worktree=%q\n' "${report_worktree}"
  printf 'state=%q\n' "${report_state}"
  printf 'action=%q\n' "${report_action}"
  printf 'db_path=%q\n' "${report_db_path}"
  printf 'message=%q\n' "${report_message}"
  printf 'notice=%q\n' "${report_notice}"
  printf 'bootstrap_source=%q\n' "${report_bootstrap_source}"
  printf 'runtime_repair_mode=%q\n' "${report_runtime_repair_mode}"
}

render_human() {
  printf 'Worktree: %s\n' "${report_worktree}"
  printf 'State: %s\n' "${report_state}"
  printf 'Action: %s\n' "${report_action}"
  printf 'DB Path: %s\n' "${report_db_path}"
  printf 'Message: %s\n' "${report_message}"
  if [[ -n "${report_bootstrap_source}" ]]; then
    printf 'Bootstrap Source: %s\n' "${report_bootstrap_source}"
  fi
  if [[ -n "${report_runtime_repair_mode}" ]]; then
    printf 'Runtime Repair Mode: %s\n' "${report_runtime_repair_mode}"
  fi
  if [[ -n "${report_notice}" ]]; then
    printf 'Notice: %s\n' "${report_notice}"
  fi
}

main() {
  parse_args "$@"
  ensure_worktree_context
  classify_state

  if [[ "${check_only}" != "true" ]]; then
    if [[ "${report_action}" == "stop_and_report" && \
          "${report_runtime_repair_mode}" != "rebuild_local_foundation" && \
          "${report_runtime_repair_mode}" != "repair_runtime_only" ]]; then
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
