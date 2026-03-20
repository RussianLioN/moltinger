#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/beads-resolve-db.sh
source "${REPO_ROOT}/scripts/beads-resolve-db.sh"

INVENTORY_SCHEMA="beads-dolt-inventory/v1"
TARGET_CONTRACT_NAME="dolt-native"
TARGET_CONTRACT_SUMMARY="Staged migration to one Dolt-native Beads contract with report-only readiness before pilot cutover."

repo_override=""
output_format="human"
output_path=""
gate_name=""
report_repo_root=""
report_canonical_root=""
report_json=""

declare -a INVENTORY_SURFACES=()
declare -a INVENTORY_WORKTREES=()

inventory_usage() {
  cat <<'EOF'
Usage:
  scripts/beads-dolt-migration-inventory.sh [--repo <path>] [--format <human|json|env>] [--output <path>] [--gate pilot]

Description:
  Build a deterministic inventory of legacy Beads surfaces and a machine-readable
  readiness report. This phase is report-only and intentionally does not perform
  pilot cutover, rollout, or rollback actions.

Options:
  --repo <path>      Inspect a different repository root or worktree
  --format <value>   Output format: human, json, env (default: human)
  --output <path>    Write the rendered report to a file instead of stdout
  --gate pilot       Exit non-zero when pilot cutover must remain blocked
  -h, --help         Show this help text
EOF
}

inventory_die() {
  echo "[beads-dolt-migration-inventory] $*" >&2
  exit 2
}

inventory_require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || inventory_die "Required command not found: ${command_name}"
}

inventory_bool_json() {
  local value="${1:-false}"
  case "${value}" in
    true|false)
      printf '%s\n' "${value}"
      ;;
    *)
      inventory_die "invalid boolean value: ${value}"
      ;;
  esac
}

inventory_json_array_from_args() {
  if [[ $# -eq 0 ]]; then
    printf '[]\n'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -cs .
}

inventory_json_array_from_objects() {
  if [[ $# -eq 0 ]]; then
    printf '[]\n'
    return 0
  fi
  printf '%s\n' "$@" | jq -cs .
}

inventory_normalize_path() {
  local input_path="$1"
  local base_path="${2:-$PWD}"

  if [[ -z "${input_path}" ]]; then
    return 1
  fi

  if [[ "${input_path}" == /* ]]; then
    (
      cd "$(dirname "${input_path}")"
      printf '%s/%s\n' "$(pwd -P)" "$(basename "${input_path}")"
    )
    return 0
  fi

  (
    cd "${base_path}"
    cd "$(dirname "${input_path}")"
    printf '%s/%s\n' "$(pwd -P)" "$(basename "${input_path}")"
  )
}

inventory_git() {
  env \
    -u GIT_DIR \
    -u GIT_WORK_TREE \
    -u GIT_COMMON_DIR \
    -u GIT_NAMESPACE \
    -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY \
    -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    -u GIT_PREFIX \
    -u GIT_CEILING_DIRECTORIES \
    -u GIT_DISCOVERY_ACROSS_FILESYSTEM \
    git "$@"
}

inventory_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo_override="${2:-}"
        [[ -n "${repo_override}" ]] || inventory_die "--repo requires a value"
        shift 2
        ;;
      --format)
        output_format="${2:-}"
        [[ -n "${output_format}" ]] || inventory_die "--format requires a value"
        shift 2
        ;;
      --output)
        output_path="${2:-}"
        [[ -n "${output_path}" ]] || inventory_die "--output requires a value"
        shift 2
        ;;
      --gate)
        gate_name="${2:-}"
        [[ -n "${gate_name}" ]] || inventory_die "--gate requires a value"
        shift 2
        ;;
      -h|--help)
        inventory_usage
        exit 0
        ;;
      *)
        inventory_die "Unknown argument: $1"
        ;;
    esac
  done

  case "${output_format}" in
    human|json|env) ;;
    *)
      inventory_die "Unsupported output format: ${output_format}"
      ;;
  esac

  case "${gate_name}" in
    ""|pilot) ;;
    *)
      inventory_die "Unsupported gate: ${gate_name}"
      ;;
  esac
}

inventory_repo_root() {
  local probe_path="${1:-$PWD}"
  local repo_root=""

  repo_root="$(beads_resolve_repo_root "${probe_path}" 2>/dev/null || true)"
  [[ -n "${repo_root}" ]] || inventory_die "Could not determine repo root for ${probe_path}"
  printf '%s\n' "${repo_root}"
}

inventory_canonical_root() {
  local repo_root="$1"
  local canonical_root=""

  canonical_root="$(beads_resolve_canonical_root "${repo_root}" 2>/dev/null || true)"
  if [[ -z "${canonical_root}" ]]; then
    canonical_root="${repo_root}"
  fi
  printf '%s\n' "${canonical_root}"
}

inventory_relpath_abs() {
  local relpath="$1"
  printf '%s/%s\n' "${report_repo_root}" "${relpath}"
}

inventory_git_tracked() {
  local relpath="$1"
  inventory_git -C "${report_repo_root}" ls-files --error-unmatch -- "${relpath}" >/dev/null 2>&1
}

inventory_file_contains() {
  local filepath="$1"
  local needle="$2"

  [[ -f "${filepath}" ]] || return 1
  grep -Fq -- "${needle}" "${filepath}"
}

inventory_add_surface() {
  local id="$1"
  local area="$2"
  local relpath="$3"
  local observed="$4"
  local classification="$5"
  local readiness="$6"
  local blocking="$7"
  local summary="$8"
  local reason="$9"
  local signals_json="${10:-[]}"

  local abs_path=""
  if [[ -n "${relpath}" ]]; then
    abs_path="$(inventory_relpath_abs "${relpath}")"
  fi

  INVENTORY_SURFACES+=("$(
    jq -nc \
      --arg id "${id}" \
      --arg area "${area}" \
      --arg relpath "${relpath}" \
      --arg path "${abs_path}" \
      --arg classification "${classification}" \
      --arg readiness "${readiness}" \
      --arg summary "${summary}" \
      --arg reason "${reason}" \
      --argjson observed "$(inventory_bool_json "${observed}")" \
      --argjson blocking "$(inventory_bool_json "${blocking}")" \
      --argjson signals "${signals_json}" \
      '{
        id: $id,
        area: $area,
        path: (if $relpath == "" then null else $path end),
        relpath: (if $relpath == "" then null else $relpath end),
        observed: $observed,
        classification: $classification,
        readiness: $readiness,
        blocking: $blocking,
        summary: $summary,
        reason: $reason,
        signals: $signals
      }'
  )")
}

inventory_add_file_surface() {
  local id="$1"
  local area="$2"
  local relpath="$3"
  local observe_if_present="$4"
  local classification_when_observed="$5"
  local readiness_when_observed="$6"
  local blocking_when_observed="$7"
  local summary="$8"
  local reason_when_observed="$9"
  local reason_when_absent="${10}"
  shift 10

  local abs_path=""
  local observed="false"
  local exists="false"
  local tracked="false"
  local -a signals=()
  local classification="already-compatible"
  local readiness="ready"
  local blocking="false"
  local reason="${reason_when_absent}"

  abs_path="$(inventory_relpath_abs "${relpath}")"
  if [[ -e "${abs_path}" ]]; then
    exists="true"
    signals+=("present")
  fi
  if inventory_git_tracked "${relpath}"; then
    tracked="true"
    signals+=("tracked")
  fi
  if [[ "${observe_if_present}" == "true" && ( "${exists}" == "true" || "${tracked}" == "true" ) ]]; then
    observed="true"
  fi

  while [[ $# -gt 1 ]]; do
    local signal_label="$1"
    local signal_needle="$2"
    shift 2
    if inventory_file_contains "${abs_path}" "${signal_needle}"; then
      observed="true"
      signals+=("${signal_label}")
    fi
  done

  if [[ "${observed}" == "true" ]]; then
    classification="${classification_when_observed}"
    readiness="${readiness_when_observed}"
    blocking="${blocking_when_observed}"
    reason="${reason_when_observed}"
  fi

  inventory_add_surface \
    "${id}" \
    "${area}" \
    "${relpath}" \
    "${observed}" \
    "${classification}" \
    "${readiness}" \
    "${blocking}" \
    "${summary}" \
    "${reason}" \
    "$(inventory_json_array_from_args "${signals[@]}")"
}

inventory_add_pilot_aware_surface() {
  local id="$1"
  local area="$2"
  local relpath="$3"
  local summary="$4"
  local legacy_reason="$5"
  local pilot_bridge_reason="$6"
  local reason_when_absent="$7"
  shift 7

  local abs_path=""
  local observed="false"
  local classification="already-compatible"
  local readiness="ready"
  local blocking="false"
  local reason="${reason_when_absent}"
  local legacy_present="false"
  local pilot_bridge_present="false"
  local -a signals=()

  abs_path="$(inventory_relpath_abs "${relpath}")"
  [[ -e "${abs_path}" ]] && signals+=("present")
  inventory_git_tracked "${relpath}" && signals+=("tracked")

  while [[ $# -gt 2 ]]; do
    local signal_label="$1"
    local signal_needle="$2"
    local signal_kind="$3"
    shift 3
    if inventory_file_contains "${abs_path}" "${signal_needle}"; then
      observed="true"
      signals+=("${signal_label}")
      if [[ "${signal_kind}" == "legacy" ]]; then
        legacy_present="true"
      fi
      if [[ "${signal_kind}" == "pilot" ]]; then
        pilot_bridge_present="true"
      fi
    fi
  done

  if [[ "${pilot_bridge_present}" == "true" ]]; then
    classification="can-bridge"
    readiness="warning"
    blocking="false"
    reason="${pilot_bridge_reason}"
  elif [[ "${legacy_present}" == "true" ]]; then
    classification="must-migrate"
    readiness="blocked"
    blocking="true"
    reason="${legacy_reason}"
  fi

  inventory_add_surface \
    "${id}" \
    "${area}" \
    "${relpath}" \
    "${observed}" \
    "${classification}" \
    "${readiness}" \
    "${blocking}" \
    "${summary}" \
    "${reason}" \
    "$(inventory_json_array_from_args "${signals[@]}")"
}

inventory_run_bd_command() {
  local repo_root="$1"
  shift

  (
    cd "${repo_root}"
    "$@" 2>/dev/null
  )
}

inventory_collect_runtime_surfaces() {
  local command_path=""
  local normalized_command_path=""
  local bd_version=""
  local info_output=""
  local backend_output=""
  local info_db=""
  local info_mode=""
  local info_reason=""
  local backend_name=""
  local backend_beads_dir=""
  local backend_db=""
  local command_classification="already-compatible"
  local command_readiness="ready"
  local command_blocking="false"
  local command_reason="System bd command path does not depend on a repo-local shim."
  local info_classification="blocked"
  local info_readiness="blocked"
  local info_blocking="true"
  local info_reason_detail="Could not collect 'bd --no-daemon info' from the current worktree."
  local backend_classification="blocked"
  local backend_readiness="blocked"
  local backend_blocking="true"
  local backend_reason_detail="Could not collect 'bd backend show' from the current worktree."
  local -a command_signals=()
  local -a info_signals=()
  local -a backend_signals=()

  command_path="$(command -v bd 2>/dev/null || true)"
  if [[ -n "${command_path}" ]]; then
    normalized_command_path="$(inventory_normalize_path "${command_path}" "${report_repo_root}" 2>/dev/null || printf '%s\n' "${command_path}")"
    command_signals+=("command-available")
    if [[ -x "${report_repo_root}/bin/bd" && ( "${normalized_command_path}" == "${report_repo_root}/bin/bd" || ":${PATH}:" == *":${report_repo_root}/bin:"* ) ]]; then
      command_classification="can-bridge"
      command_readiness="warning"
      command_reason="Repo-local plain bd shim remains the active command path and will need an explicit target-contract decision before cutover."
      command_signals+=("repo-local-shim")
    fi
    if [[ "${normalized_command_path}" != "${command_path}" ]]; then
      command_signals+=("normalized-command:${normalized_command_path}")
    fi
  else
    command_classification="blocked"
    command_readiness="blocked"
    command_blocking="true"
    command_reason="No bd command is available in PATH for the inspected worktree."
    command_signals+=("command-missing")
  fi

  bd_version="$(inventory_run_bd_command "${report_repo_root}" bd --version || true)"
  if [[ -n "${bd_version}" ]]; then
    command_signals+=("version:${bd_version}")
  fi

  inventory_add_surface \
    "runtime.command_path" \
    "runtime" \
    "" \
    "true" \
    "${command_classification}" \
    "${command_readiness}" \
    "${command_blocking}" \
    "Current bd command path" \
    "${command_reason}" \
    "$(inventory_json_array_from_args "${command_signals[@]}")"

  info_output="$(inventory_run_bd_command "${report_repo_root}" bd --no-daemon info || true)"
  if [[ -n "${info_output}" ]]; then
    info_db="$(printf '%s\n' "${info_output}" | sed -n 's/^Database: //p' | head -1)"
    info_mode="$(printf '%s\n' "${info_output}" | sed -n 's/^Mode: //p' | head -1)"
    info_reason="$(printf '%s\n' "${info_output}" | sed -n 's/^  Reason: //p' | head -1)"
    if [[ -n "${info_db}" ]]; then
      info_signals+=("db:${info_db}")
    fi
    if [[ -n "${info_mode}" ]]; then
      info_signals+=("mode:${info_mode}")
    fi
    if [[ -n "${info_reason}" ]]; then
      info_signals+=("reason:${info_reason}")
    fi

    if [[ -n "${info_db}" && "${info_db}" == "${report_repo_root}/.beads/"* ]]; then
      info_classification="already-compatible"
      info_readiness="ready"
      info_blocking="false"
      info_reason_detail="Read-only no-daemon info resolves to the current worktree-local Beads database."
      info_signals+=("worktree-local-db")
    elif [[ -n "${info_db}" && "${report_repo_root}" != "${report_canonical_root}" && "${info_db}" == "${report_canonical_root}/.beads/"* ]]; then
      info_classification="blocked"
      info_readiness="blocked"
      info_blocking="true"
      info_reason_detail="Read-only no-daemon info still resolves to the canonical-root tracker instead of the current worktree."
      info_signals+=("canonical-root-coupling")
    else
      info_classification="warning"
      info_readiness="warning"
      info_blocking="false"
      info_reason_detail="Read-only no-daemon info produced a non-standard Beads database path that still needs migration review."
      info_signals+=("non-standard-db")
    fi
  else
    info_signals+=("info-command-failed")
  fi

  inventory_add_surface \
    "runtime.no_daemon_info" \
    "runtime" \
    "" \
    "true" \
    "${info_classification}" \
    "${info_readiness}" \
    "${info_blocking}" \
    "Current worktree no-daemon runtime" \
    "${info_reason_detail}" \
    "$(inventory_json_array_from_args "${info_signals[@]}")"

  backend_output="$(inventory_run_bd_command "${report_repo_root}" bd backend show || true)"
  if [[ -n "${backend_output}" ]]; then
    backend_name="$(printf '%s\n' "${backend_output}" | sed -n 's/^Current backend: //p' | head -1)"
    backend_beads_dir="$(printf '%s\n' "${backend_output}" | sed -n 's/^  Beads dir: //p' | head -1)"
    backend_db="$(printf '%s\n' "${backend_output}" | sed -n 's/^  Database: //p' | head -1)"
    if [[ -n "${backend_name}" ]]; then
      backend_signals+=("backend:${backend_name}")
    fi
    if [[ -n "${backend_beads_dir}" ]]; then
      backend_signals+=("beads-dir:${backend_beads_dir}")
    fi
    if [[ -n "${backend_db}" ]]; then
      backend_signals+=("database:${backend_db}")
    fi

    if [[ "${backend_name}" != "dolt" ]]; then
      backend_classification="blocked"
      backend_readiness="blocked"
      backend_blocking="true"
      backend_reason_detail="The active backend is not Dolt yet, so pilot cutover must stay blocked."
      backend_signals+=("backend-not-dolt")
    elif [[ -n "${backend_beads_dir}" && "${backend_beads_dir}" != "${report_repo_root}/.beads" ]]; then
      backend_classification="blocked"
      backend_readiness="blocked"
      backend_blocking="true"
      backend_reason_detail="Backend metadata still points at a different Beads directory than the inspected worktree."
      backend_signals+=("backend-dir-mismatch")
    else
      backend_classification="already-compatible"
      backend_readiness="ready"
      backend_blocking="false"
      backend_reason_detail="Backend metadata already matches a Dolt-native worktree-local target."
      backend_signals+=("backend-ready")
    fi
  else
    backend_signals+=("backend-command-failed")
  fi

  inventory_add_surface \
    "runtime.backend_state" \
    "runtime" \
    "" \
    "true" \
    "${backend_classification}" \
    "${backend_readiness}" \
    "${backend_blocking}" \
    "Current backend state" \
    "${backend_reason_detail}" \
    "$(inventory_json_array_from_args "${backend_signals[@]}")"
}

inventory_collect_file_surfaces() {
  inventory_add_file_surface \
    "tracked.issues_jsonl" \
    "tracked-artifact" \
    ".beads/issues.jsonl" \
    "true" \
    "must-migrate" \
    "blocked" \
    "true" \
    "Tracked JSONL issue surface" \
    "Tracked .beads/issues.jsonl is still present and keeps JSONL-first issue reasoning in the repo contract." \
    "Tracked .beads/issues.jsonl is absent from the inspected repo root." \
    "jsonl-path" ".beads/issues.jsonl"

  inventory_add_file_surface \
    "tracked.config_yaml" \
    "tracked-artifact" \
    ".beads/config.yaml" \
    "true" \
    "can-bridge" \
    "warning" \
    "false" \
    "Tracked Beads config" \
    "Tracked Beads configuration remains part of the legacy-to-target compatibility surface and still needs target-contract review." \
    "Tracked Beads configuration is absent from the inspected repo root."

  inventory_add_file_surface \
    "bootstrap.envrc" \
    "bootstrap" \
    ".envrc" \
    "false" \
    "can-bridge" \
    "warning" \
    "false" \
    "Repo-local PATH bootstrap" \
    "The repo bootstrap still pins plain bd through .envrc and must be reviewed against the target contract." \
    "No repo-local .envrc bootstrap was found." \
    "repo-local-bd-path" '/bin:${PATH}'

  inventory_add_file_surface \
    "script.bin_bd" \
    "script" \
    "bin/bd" \
    "true" \
    "can-bridge" \
    "warning" \
    "false" \
    "Repo-local bd shim" \
    "A repo-local bd shim is still present and currently mediates the active operator path." \
    "No repo-local bd shim is present at bin/bd." \
    "resolver-hook" "beads-resolve-db.sh"

  inventory_add_file_surface \
    "script.beads_resolve_db" \
    "script" \
    "scripts/beads-resolve-db.sh" \
    "true" \
    "can-bridge" \
    "warning" \
    "false" \
    "Beads ownership resolver" \
    "The repo still relies on a legacy/locality resolver to decide how plain bd dispatches." \
    "No Beads ownership resolver was found in scripts/beads-resolve-db.sh."

  inventory_add_file_surface \
    "script.beads_worktree_localize" \
    "script" \
    "scripts/beads-worktree-localize.sh" \
    "true" \
    "can-bridge" \
    "warning" \
    "false" \
    "Beads worktree localizer" \
    "The compatibility localizer remains part of the migration bridge for worktree ownership repair." \
    "No Beads worktree localizer was found."

  inventory_add_file_surface \
    "script.beads_normalize_issues_jsonl" \
    "script" \
    "scripts/beads-normalize-issues-jsonl.sh" \
    "true" \
    "can-remove" \
    "warning" \
    "false" \
    "Tracked JSONL normalizer" \
    "The repo still ships a dedicated .beads/issues.jsonl normalizer. It can remain only as an explicitly retired or compatibility-only surface." \
    "No tracked JSONL normalizer was found."

  inventory_add_file_surface \
    "script.worktree_ready" \
    "script" \
    "scripts/worktree-ready.sh" \
    "false" \
    "can-bridge" \
    "warning" \
    "false" \
    "Managed worktree bootstrap flow" \
    "The managed worktree bootstrap flow still references plain bd workflow details that will need migration alignment." \
    "No managed worktree bootstrap flow was found." \
    "plain-bd" 'plain `bd`' \
    "bd-sync" "bd sync"

  inventory_add_pilot_aware_surface \
    "hook.pre_commit" \
    "hook" \
    ".githooks/pre-commit" \
    "Pre-commit hook legacy Beads checks" \
    "The pre-commit hook still enforces legacy JSONL or legacy ownership behavior and must be migrated before pilot cutover." \
    "The pre-commit hook now contains an explicit pilot-mode guard that blocks staged JSONL and bridges the legacy normalization path." \
    "No legacy Beads markers were detected in .githooks/pre-commit." \
    "normalizes-jsonl" "beads-normalize-issues-jsonl.sh" "legacy" \
    "issues-jsonl" ".beads/issues.jsonl" "legacy" \
    "worktree-audit" "beads-worktree-audit.sh" "legacy" \
    "pilot-mode-file" "pilot-mode.json" "pilot" \
    "pilot-review" "beads-dolt-pilot.sh review" "pilot"

  inventory_add_file_surface \
    "hook.post_checkout" \
    "hook" \
    ".githooks/post-checkout" \
    "false" \
    "can-bridge" \
    "warning" \
    "false" \
    "Post-checkout compatibility hook" \
    "The post-checkout hook still contains Beads compatibility repair logic that must be revisited for the target contract." \
    "No Beads compatibility markers were detected in .githooks/post-checkout." \
    "localize" "beads-worktree-localize.sh"

  inventory_add_file_surface \
    "hook.post_merge" \
    "hook" \
    ".githooks/post-merge" \
    "false" \
    "can-bridge" \
    "warning" \
    "false" \
    "Post-merge compatibility hook" \
    "The post-merge hook still contains Beads compatibility repair logic that must be revisited for the target contract." \
    "No Beads compatibility markers were detected in .githooks/post-merge." \
    "localize" "beads-worktree-localize.sh"

  inventory_add_file_surface \
    "hook.pre_push" \
    "hook" \
    ".githooks/pre-push" \
    "false" \
    "can-bridge" \
    "warning" \
    "false" \
    "Pre-push Beads audit hook" \
    "The pre-push hook still runs Beads ownership audit logic that should be reviewed before cutover." \
    "No Beads audit markers were detected in .githooks/pre-push." \
    "worktree-audit" "beads-worktree-audit.sh"

  inventory_add_file_surface \
    "doc.root_agents" \
    "doc" \
    "AGENTS.md" \
    "false" \
    "must-migrate" \
    "blocked" \
    "true" \
    "Root agent instructions" \
    "Root agent instructions still prescribe legacy Beads sync behavior that would make the active operator path ambiguous during pilot." \
    "No legacy Beads sync markers were detected in AGENTS.md." \
    "bd-sync" "bd sync"

  inventory_add_pilot_aware_surface \
    "doc.beads_agents" \
    "doc" \
    ".beads/AGENTS.md" \
    "Tracked Beads state instructions" \
    "Tracked Beads state instructions still prescribe bd sync as part of the everyday workflow." \
    "Tracked Beads state instructions now include pilot-mode guidance and can bridge the repo while ordinary legacy text is still being retired." \
    "No legacy Beads sync markers were detected in .beads/AGENTS.md." \
    "bd-sync" "bd sync" "legacy" \
    "pilot-mode-file" "pilot-mode.json" "pilot" \
    "pilot-review" "beads-dolt-pilot.sh review" "pilot"

  inventory_add_pilot_aware_surface \
    "doc.quickstart_ru" \
    "doc" \
    ".claude/docs/beads-quickstart.md" \
    "Russian Beads quickstart" \
    "The Russian quickstart still documents legacy Beads sync behavior and must be rewritten before pilot cutover." \
    "The Russian quickstart now contains explicit pilot-mode guidance and can bridge the repo while ordinary legacy text is still being retired." \
    "No legacy Beads sync markers were detected in the Russian quickstart." \
    "bd-sync" "bd sync" "legacy" \
    "session-close" "SESSION CLOSE PROTOCOL" "legacy" \
    "pilot-mode-file" "pilot-mode.json" "pilot" \
    "pilot-review" "beads-dolt-pilot.sh review" "pilot"

  inventory_add_pilot_aware_surface \
    "doc.quickstart_en" \
    "doc" \
    ".claude/docs/beads-quickstart.en.md" \
    "English Beads quickstart" \
    "The English quickstart still documents legacy Beads sync behavior and must be rewritten before pilot cutover." \
    "The English quickstart now contains explicit pilot-mode guidance and can bridge the repo while ordinary legacy text is still being retired." \
    "No legacy Beads sync markers were detected in the English quickstart." \
    "bd-sync" "bd sync" "legacy" \
    "session-close" "SESSION CLOSE PROTOCOL" "legacy" \
    "pilot-mode-file" "pilot-mode.json" "pilot" \
    "pilot-review" "beads-dolt-pilot.sh review" "pilot"

  inventory_add_pilot_aware_surface \
    "skill.commands_quickref" \
    "skill" \
    ".claude/skills/beads/resources/COMMANDS_QUICKREF.md" \
    "Beads command quick reference" \
    "The Beads command quick reference still documents legacy sync behavior that conflicts with the target contract boundary." \
    "The Beads command quick reference now contains explicit pilot-mode guidance and can bridge the repo while ordinary legacy text is still being retired." \
    "No legacy Beads sync markers were detected in the command quick reference." \
    "bd-sync" "bd sync" "legacy" \
    "pilot-mode-file" "pilot-mode.json" "pilot" \
    "pilot-review" "beads-dolt-pilot.sh review" "pilot"

  inventory_add_pilot_aware_surface \
    "skill.workflows" \
    "skill" \
    ".claude/skills/beads/resources/WORKFLOWS.md" \
    "Beads workflows reference" \
    "The Beads workflows reference still documents legacy sync behavior that conflicts with the target contract boundary." \
    "The Beads workflows reference now contains explicit pilot-mode guidance and can bridge the repo while ordinary legacy text is still being retired." \
    "No legacy Beads sync markers were detected in the workflows reference." \
    "bd-sync" "bd sync" "legacy" \
    "pilot-mode-file" "pilot-mode.json" "pilot" \
    "pilot-review" "beads-dolt-pilot.sh review" "pilot"

  inventory_add_file_surface \
    "test.static_beads_worktree_ownership" \
    "test" \
    "tests/static/test_beads_worktree_ownership.sh" \
    "false" \
    "must-migrate" \
    "warning" \
    "false" \
    "Legacy Beads static contract test" \
    "Existing static tests still encode legacy Beads surfaces that will need explicit migration updates." \
    "No legacy Beads markers were detected in the static ownership test." \
    "issues-jsonl" ".beads/issues.jsonl" \
    "normalize" "beads-normalize-issues-jsonl.sh"

  inventory_add_file_surface \
    "test.unit_bd_dispatch" \
    "test" \
    "tests/unit/test_bd_dispatch.sh" \
    "false" \
    "must-migrate" \
    "warning" \
    "false" \
    "Legacy Beads dispatch unit test" \
    "Existing dispatch tests still encode legacy/localization behavior that must be reviewed as part of the migration." \
    "No legacy Beads markers were detected in the dispatch unit test." \
    "issues-jsonl" ".beads/issues.jsonl" \
    "localize" "beads-worktree-localize.sh"

  inventory_add_file_surface \
    "test.unit_beads_worktree_audit" \
    "test" \
    "tests/unit/test_beads_worktree_audit.sh" \
    "false" \
    "must-migrate" \
    "warning" \
    "false" \
    "Legacy Beads worktree audit unit test" \
    "Existing worktree audit tests still encode compatibility behavior that must be reviewed as part of the migration." \
    "No legacy Beads markers were detected in the worktree audit unit test." \
    "localize" "beads-worktree-localize.sh" \
    "audit" "beads-worktree-audit.sh"

  inventory_add_file_surface \
    "test.unit_beads_normalize_issues_jsonl" \
    "test" \
    "tests/unit/test_beads_normalize_issues_jsonl.sh" \
    "true" \
    "must-migrate" \
    "warning" \
    "false" \
    "Tracked JSONL normalization unit test" \
    "A dedicated normalization test still exists for tracked .beads/issues.jsonl, so migration cannot treat JSONL as retired yet." \
    "No dedicated tracked JSONL normalization unit test was found."
}

inventory_collect_worktree_paths() {
  inventory_git -C "${report_repo_root}" worktree list --porcelain | awk '
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
  ' | LC_ALL=C sort
}

inventory_worktree_branch() {
  local worktree_path="$1"
  local branch_name=""

  branch_name="$(inventory_git -C "${worktree_path}" branch --show-current 2>/dev/null || true)"
  if [[ -z "${branch_name}" ]]; then
    branch_name="DETACHED"
  fi
  printf '%s\n' "${branch_name}"
}

inventory_add_worktree() {
  local path="$1"
  local branch="$2"
  local state="$3"
  local classification="$4"
  local readiness="$5"
  local blocking="$6"
  local current="$7"
  local reason="$8"
  local signals_json="${9:-[]}"

  INVENTORY_WORKTREES+=("$(
    jq -nc \
      --arg path "${path}" \
      --arg branch "${branch}" \
      --arg state "${state}" \
      --arg classification "${classification}" \
      --arg readiness "${readiness}" \
      --arg reason "${reason}" \
      --argjson blocking "$(inventory_bool_json "${blocking}")" \
      --argjson current "$(inventory_bool_json "${current}")" \
      --argjson signals "${signals_json}" \
      '{
        path: $path,
        branch: $branch,
        state: $state,
        classification: $classification,
        readiness: $readiness,
        blocking: $blocking,
        current: $current,
        reason: $reason,
        signals: $signals
      }'
  )")
}

inventory_classify_worktree() {
  local worktree_path="$1"
  local branch_name=""
  local beads_dir=""
  local config_path=""
  local issues_path=""
  local db_path=""
  local redirect_path=""
  local envrc_path=""
  local bin_bd_path=""
  local resolve_path=""
  local state="no_beads"
  local classification="already-compatible"
  local readiness="ready"
  local blocking="false"
  local reason="No Beads state was found in this worktree."
  local current="false"
  local -a signals=()

  if [[ "${worktree_path}" == "${report_repo_root}" ]]; then
    current="true"
  fi

  branch_name="$(inventory_worktree_branch "${worktree_path}")"
  beads_dir="${worktree_path}/.beads"
  config_path="${beads_dir}/config.yaml"
  issues_path="${beads_dir}/issues.jsonl"
  db_path="${beads_dir}/beads.db"
  redirect_path="${beads_dir}/redirect"
  envrc_path="${worktree_path}/.envrc"
  bin_bd_path="${worktree_path}/bin/bd"
  resolve_path="${worktree_path}/scripts/beads-resolve-db.sh"

  [[ -f "${config_path}" ]] && signals+=("config")
  [[ -f "${issues_path}" ]] && signals+=("issues-jsonl")
  [[ -f "${db_path}" ]] && signals+=("beads-db")
  [[ -f "${redirect_path}" ]] && signals+=("redirect")
  [[ -f "${envrc_path}" ]] && signals+=("envrc")
  [[ -f "${bin_bd_path}" ]] && signals+=("bin-bd")
  [[ -f "${resolve_path}" ]] && signals+=("resolver")

  if [[ -f "${redirect_path}" ]]; then
    if [[ ! -f "${envrc_path}" || ! -f "${bin_bd_path}" || ! -f "${resolve_path}" ]]; then
      state="bootstrap_variance"
      classification="blocked"
      readiness="blocked"
      blocking="true"
      reason="This worktree still carries redirect residue and is also missing bootstrap files required for a safe migration path."
    elif [[ -f "${config_path}" && -f "${issues_path}" ]]; then
      state="migratable_legacy"
      classification="must-migrate"
      readiness="blocked"
      blocking="true"
      reason="This worktree still carries redirect residue tied to legacy JSONL-first Beads state."
    else
      state="redirect_blocked"
      classification="blocked"
      readiness="blocked"
      blocking="true"
      reason="This worktree still carries redirect residue and does not have enough local Beads foundation to classify it as safely migratable."
    fi
  elif [[ -f "${config_path}" && -f "${issues_path}" && -f "${db_path}" ]]; then
    state="legacy_jsonl_first"
    classification="must-migrate"
    readiness="blocked"
    blocking="true"
    reason="This worktree still combines tracked issues.jsonl with a local sqlite Beads database."
  elif [[ -f "${config_path}" && -f "${db_path}" && ! -f "${issues_path}" ]]; then
    state="pilot_ready_candidate"
    classification="already-compatible"
    readiness="ready"
    blocking="false"
    reason="This worktree has local config plus local database without tracked JSONL residue."
  elif [[ -f "${config_path}" && -f "${issues_path}" ]]; then
    state="partial_foundation"
    classification="can-bridge"
    readiness="blocked"
    blocking="true"
    reason="This worktree still has tracked JSONL state without a complete local runtime foundation."
  elif [[ -d "${beads_dir}" ]]; then
    state="missing_foundation"
    classification="blocked"
    readiness="blocked"
    blocking="true"
    reason="This worktree has an incomplete .beads directory and cannot be considered pilot-ready."
  fi

  inventory_add_worktree \
    "${worktree_path}" \
    "${branch_name}" \
    "${state}" \
    "${classification}" \
    "${readiness}" \
    "${blocking}" \
    "${current}" \
    "${reason}" \
    "$(inventory_json_array_from_args "${signals[@]}")"
}

inventory_collect_worktrees() {
  local worktree_path=""

  while IFS= read -r worktree_path; do
    [[ -n "${worktree_path}" ]] || continue
    inventory_classify_worktree "${worktree_path}"
  done < <(inventory_collect_worktree_paths)
}

inventory_build_report_json() {
  local surfaces_json=""
  local worktrees_json=""

  surfaces_json="$(inventory_json_array_from_objects "${INVENTORY_SURFACES[@]}")"
  worktrees_json="$(inventory_json_array_from_objects "${INVENTORY_WORKTREES[@]}")"

  report_json="$(
    jq -S -n \
      --arg schema "${INVENTORY_SCHEMA}" \
      --arg repo_root "${report_repo_root}" \
      --arg canonical_root "${report_canonical_root}" \
      --arg target_contract_name "${TARGET_CONTRACT_NAME}" \
      --arg target_contract_summary "${TARGET_CONTRACT_SUMMARY}" \
      --argjson surfaces "${surfaces_json}" \
      --argjson worktrees "${worktrees_json}" \
      '
      def blockers:
        (
          [$surfaces[] | select(.blocking) | {
            id: .id,
            source: "surface",
            classification: .classification,
            path: .path,
            reason: .reason
          }] +
          [$worktrees[] | select(.blocking) | {
            id: ("worktree:" + .path),
            source: "worktree",
            classification: .classification,
            path: .path,
            reason: .reason
          }]
        );
      def warning_count:
        ([$surfaces[] | select(.readiness == "warning")] | length) +
        ([$worktrees[] | select(.readiness == "warning")] | length);
      def verdict:
        if (blockers | length) > 0 then "blocked"
        elif warning_count > 0 then "warning"
        else "ready"
        end;
      {
        schema: $schema,
        repo_root: $repo_root,
        canonical_root: $canonical_root,
        target_contract: {
          name: $target_contract_name,
          summary: $target_contract_summary
        },
        summary: {
          verdict: verdict,
          pilot_gate: (if (blockers | length) > 0 then "blocked" else "pass" end),
          surface_count: ($surfaces | length),
          observed_surface_count: ([$surfaces[] | select(.observed)] | length),
          worktree_count: ($worktrees | length),
          blocking_count: (blockers | length),
          warning_count: warning_count
        },
        surfaces: $surfaces,
        worktrees: $worktrees,
        blockers: blockers
      }'
  )"
}

inventory_render_human() {
  printf '%s\n' "${report_json}" | jq -r '
    [
      "Schema: \(.schema)",
      "Repo Root: \(.repo_root)",
      "Canonical Root: \(.canonical_root)",
      "Target Contract: \(.target_contract.name)",
      "Verdict: \(.summary.verdict)",
      "Pilot Gate: \(.summary.pilot_gate)",
      "Observed Surfaces: \(.summary.observed_surface_count)/\(.summary.surface_count)",
      "Worktrees: \(.summary.worktree_count)",
      "Blocking Items: \(.summary.blocking_count)",
      "Warnings: \(.summary.warning_count)",
      "",
      "Surfaces:"
    ] +
    (
      if (.surfaces | length) == 0 then
        ["  - none"]
      else
        [.surfaces[] | "  - \(.id) [\(.classification)/\(.readiness)] blocker=\(.blocking) :: \(.reason)"]
      end
    ) +
    ["", "Worktrees:"] +
    (
      if (.worktrees | length) == 0 then
        ["  - none"]
      else
        [.worktrees[] | "  - \(.path) (\(.branch)) state=\(.state) [\(.classification)/\(.readiness)] blocker=\(.blocking) :: \(.reason)"]
      end
    ) +
    ["", "Blockers:"] +
    (
      if (.blockers | length) == 0 then
        ["  - none"]
      else
        [.blockers[] | "  - \(.id) :: \(.reason)"]
      end
    )
    | .[]'
}

inventory_render_env() {
  printf '%s\n' "${report_json}" | jq -r '
    [
      "schema=\(.schema)",
      "repo_root=\(.repo_root | @sh)",
      "canonical_root=\(.canonical_root | @sh)",
      "verdict=\(.summary.verdict)",
      "pilot_gate=\(.summary.pilot_gate)",
      "surface_count=\(.summary.surface_count)",
      "observed_surface_count=\(.summary.observed_surface_count)",
      "worktree_count=\(.summary.worktree_count)",
      "blocking_count=\(.summary.blocking_count)",
      "warning_count=\(.summary.warning_count)",
      "blocking_ids=\(([.blockers[].id] | join(",")) | @sh)"
    ]
    | .[]'
}

inventory_emit_output() {
  local rendered=""

  case "${output_format}" in
    human)
      rendered="$(inventory_render_human)"
      ;;
    json)
      rendered="${report_json}"
      ;;
    env)
      rendered="$(inventory_render_env)"
      ;;
  esac

  if [[ -n "${output_path}" ]]; then
    mkdir -p "$(dirname "${output_path}")"
    printf '%s\n' "${rendered}" > "${output_path}"
  else
    printf '%s\n' "${rendered}"
  fi
}

inventory_apply_gate() {
  local pilot_gate=""

  [[ -n "${gate_name}" ]] || return 0
  pilot_gate="$(printf '%s\n' "${report_json}" | jq -r '.summary.pilot_gate')"
  if [[ "${gate_name}" == "pilot" && "${pilot_gate}" != "pass" ]]; then
    return 20
  fi
  return 0
}

main() {
  local target_repo=""

  inventory_require_command jq
  inventory_require_command git

  inventory_parse_args "$@"

  target_repo="${repo_override:-$PWD}"
  report_repo_root="$(inventory_repo_root "${target_repo}")"
  report_canonical_root="$(inventory_canonical_root "${report_repo_root}")"

  inventory_collect_runtime_surfaces
  inventory_collect_file_surfaces
  inventory_collect_worktrees
  inventory_build_report_json
  inventory_emit_output
  inventory_apply_gate
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
