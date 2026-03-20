#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/beads-resolve-db.sh
source "${REPO_ROOT}/scripts/beads-resolve-db.sh"

ROLLOUT_SCHEMA="beads-dolt-rollout/v1"
ROLLOUT_JSONL_ROLE="export_only"
subcommand="status"
repo_override=""
output_format="human"
package_id=""

declare -a target_worktrees=()

rollout_usage() {
  cat <<'EOF'
Usage:
  scripts/beads-dolt-rollout.sh [status|report-only|cutover|verify|rollback] [options]

Options:
  --repo <path>         Inspect or operate on a different worktree/repo root
  --worktree <path>     Explicit target worktree path (repeatable)
  --package-id <id>     Explicit rollback package id for cutover/rollback
  --format <value>      Output format: human, json, env (default: human)
  -h, --help            Show this help

Description:
  Stage Beads Dolt-native rollout and rollback without silently recreating the
  legacy JSONL-first operator model. Rollback is a separate, explicit path and
  always works from a saved rollback package.
EOF
}

rollout_die() {
  echo "[beads-dolt-rollout] $*" >&2
  exit 2
}

rollout_json_array_from_objects() {
  if [[ $# -eq 0 ]]; then
    printf '[]\n'
    return 0
  fi
  printf '%s\n' "$@" | jq -cs .
}

rollout_parse_args() {
  if [[ $# -gt 0 ]]; then
    case "${1}" in
      status|report-only|cutover|verify|rollback)
        subcommand="$1"
        shift
        ;;
      -h|--help)
        rollout_usage
        exit 0
        ;;
    esac
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo_override="${2:-}"
        [[ -n "${repo_override}" ]] || rollout_die "--repo requires a value"
        shift 2
        ;;
      --worktree)
        target_worktrees+=("${2:-}")
        [[ -n "${target_worktrees[-1]}" ]] || rollout_die "--worktree requires a value"
        shift 2
        ;;
      --package-id)
        package_id="${2:-}"
        [[ -n "${package_id}" ]] || rollout_die "--package-id requires a value"
        shift 2
        ;;
      --format)
        output_format="${2:-}"
        [[ -n "${output_format}" ]] || rollout_die "--format requires a value"
        shift 2
        ;;
      -h|--help)
        rollout_usage
        exit 0
        ;;
      *)
        rollout_die "Unknown argument: $1"
        ;;
    esac
  done

  case "${output_format}" in
    human|json|env) ;;
    *)
      rollout_die "Unsupported output format: ${output_format}"
      ;;
  esac
}

rollout_repo_root() {
  local probe_path="${1:-$PWD}"
  local repo_root=""

  repo_root="$(beads_resolve_repo_root "${probe_path}" 2>/dev/null || true)"
  [[ -n "${repo_root}" ]] || rollout_die "Could not determine repo root for ${probe_path}"
  printf '%s\n' "${repo_root}"
}

rollout_canonical_root() {
  local repo_root="$1"
  local canonical_root=""

  canonical_root="$(beads_resolve_canonical_root "${repo_root}" 2>/dev/null || true)"
  if [[ -z "${canonical_root}" ]]; then
    canonical_root="${repo_root}"
  fi
  printf '%s\n' "${canonical_root}"
}

rollout_inventory_json() {
  local repo_root="$1"
  (
    cd "${repo_root}"
    "${SCRIPT_DIR}/beads-dolt-migration-inventory.sh" --format json
  )
}

rollout_cutover_mode_file() {
  local worktree_path="$1"
  printf '%s/.beads/cutover-mode.json\n' "${worktree_path}"
}

rollout_pilot_mode_file() {
  local worktree_path="$1"
  printf '%s/.beads/pilot-mode.json\n' "${worktree_path}"
}

rollout_rollback_state_file() {
  local worktree_path="$1"
  printf '%s/.beads/rollback-state.json\n' "${worktree_path}"
}

rollout_packages_dir() {
  local repo_root="$1"
  printf '%s/.beads/migration/rollback-packages\n' "${repo_root}"
}

rollout_package_dir() {
  local repo_root="$1"
  local effective_package_id="$2"
  printf '%s/%s\n' "$(rollout_packages_dir "${repo_root}")" "${effective_package_id}"
}

rollout_manifest_path() {
  local repo_root="$1"
  local effective_package_id="$2"
  printf '%s/manifest.json\n' "$(rollout_package_dir "${repo_root}" "${effective_package_id}")"
}

rollout_active_mode() {
  local worktree_path="$1"

  if [[ -f "$(rollout_cutover_mode_file "${worktree_path}")" ]]; then
    printf 'cutover\n'
    return 0
  fi

  if [[ -f "$(rollout_pilot_mode_file "${worktree_path}")" ]]; then
    printf 'pilot\n'
    return 0
  fi

  if [[ -f "$(rollout_rollback_state_file "${worktree_path}")" ]]; then
    printf 'rolled-back\n'
    return 0
  fi

  printf 'none\n'
}

rollout_branch_name() {
  local worktree_path="$1"
  local branch_name=""

  branch_name="$(git -C "${worktree_path}" branch --show-current 2>/dev/null || true)"
  if [[ -z "${branch_name}" ]]; then
    branch_name="DETACHED"
  fi
  printf '%s\n' "${branch_name}"
}

rollout_inventory_record_for_path() {
  local worktree_path="$1"
  local inventory_json="$2"

  printf '%s\n' "${inventory_json}" | jq -c --arg path "${worktree_path}" '.worktrees[] | select(.path == $path)' | head -1
}

rollout_worktree_has_local_runtime() {
  local worktree_path="$1"
  local beads_dir="${worktree_path}/.beads"

  if [[ -e "${beads_dir}/beads.db" || -d "${beads_dir}/dolt" ]]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

rollout_inspect_target() {
  local worktree_path="$1"
  local inventory_json="$2"
  local inventory_record=""
  local branch_name=""
  local mode="none"
  local state="unknown"
  local classification="blocked"
  local readiness="blocked"
  local blocking="true"
  local reason="The target worktree is not part of the current rollout inventory."
  local eligible_for_cutover="false"
  local config_present="false"
  local db_present="false"
  local issues_present="false"
  local redirect_present="false"
  local pilot_mode_enabled="false"
  local cutover_mode_enabled="false"
  local rollback_state_enabled="false"
  local rollout_stage="blocked"

  inventory_record="$(rollout_inventory_record_for_path "${worktree_path}" "${inventory_json}")"
  branch_name="$(rollout_branch_name "${worktree_path}")"
  mode="$(rollout_active_mode "${worktree_path}")"

  [[ -f "${worktree_path}/.beads/config.yaml" ]] && config_present="true"
  db_present="$(rollout_worktree_has_local_runtime "${worktree_path}")"
  [[ -f "${worktree_path}/.beads/issues.jsonl" ]] && issues_present="true"
  [[ -f "${worktree_path}/.beads/redirect" ]] && redirect_present="true"
  [[ -f "$(rollout_pilot_mode_file "${worktree_path}")" ]] && pilot_mode_enabled="true"
  [[ -f "$(rollout_cutover_mode_file "${worktree_path}")" ]] && cutover_mode_enabled="true"
  [[ -f "$(rollout_rollback_state_file "${worktree_path}")" ]] && rollback_state_enabled="true"

  if [[ -n "${inventory_record}" ]]; then
    state="$(printf '%s\n' "${inventory_record}" | jq -r '.state')"
    classification="$(printf '%s\n' "${inventory_record}" | jq -r '.classification')"
    readiness="$(printf '%s\n' "${inventory_record}" | jq -r '.readiness')"
    blocking="$(printf '%s\n' "${inventory_record}" | jq -r '.blocking')"
    reason="$(printf '%s\n' "${inventory_record}" | jq -r '.reason')"
  fi

  case "${mode}" in
    cutover)
      rollout_stage="cutover"
      blocking="false"
      classification="already-compatible"
      readiness="ready"
      state="cutover_active"
      reason="This worktree is already operating under the cutover contract."
      ;;
    pilot)
      rollout_stage="pilot"
      if [[ "${state}" == "pilot_ready_candidate" && "${blocking}" != "true" ]]; then
        eligible_for_cutover="true"
        reason="This worktree already passed the pilot foundation checks and can enter controlled cutover."
      fi
      ;;
    rolled-back)
      rollout_stage="rolled-back"
      blocking="false"
      readiness="warning"
      classification="can-bridge"
      state="rolled_back"
      reason="This worktree has rollback evidence and should be re-verified before a new cutover attempt."
      ;;
    *)
      if [[ "${state}" == "pilot_ready_candidate" && "${blocking}" != "true" ]]; then
        rollout_stage="ready"
        eligible_for_cutover="true"
      elif [[ "${blocking}" == "true" ]]; then
        rollout_stage="blocked"
      else
        rollout_stage="report-only"
      fi
      ;;
  esac

  jq -nc \
    --arg path "${worktree_path}" \
    --arg branch "${branch_name}" \
    --arg inventory_state "${state}" \
    --arg classification "${classification}" \
    --arg readiness "${readiness}" \
    --arg reason "${reason}" \
    --arg mode "${mode}" \
    --arg rollout_stage "${rollout_stage}" \
    --argjson blocking "${blocking}" \
    --argjson eligible_for_cutover "${eligible_for_cutover}" \
    --argjson config_present "${config_present}" \
    --argjson db_present "${db_present}" \
    --argjson issues_present "${issues_present}" \
    --argjson redirect_present "${redirect_present}" \
    --argjson pilot_mode_enabled "${pilot_mode_enabled}" \
    --argjson cutover_mode_enabled "${cutover_mode_enabled}" \
    --argjson rollback_state_enabled "${rollback_state_enabled}" \
    '{
      path: $path,
      branch: $branch,
      inventory_state: $inventory_state,
      classification: $classification,
      readiness: $readiness,
      blocking: $blocking,
      reason: $reason,
      mode: $mode,
      rollout_stage: $rollout_stage,
      eligible_for_cutover: $eligible_for_cutover,
      config_present: $config_present,
      db_present: $db_present,
      issues_present: $issues_present,
      redirect_present: $redirect_present,
      pilot_mode_enabled: $pilot_mode_enabled,
      cutover_mode_enabled: $cutover_mode_enabled,
      rollback_state_enabled: $rollback_state_enabled
    }'
}

rollout_collect_targets() {
  local repo_root="$1"
  local inventory_json="$2"
  local default_scope="$3"
  local worktree_path=""
  local normalized_path=""
  local -a statuses=()

  if [[ "${#target_worktrees[@]}" -eq 0 ]]; then
    case "${default_scope}" in
      all)
        while IFS= read -r worktree_path; do
          [[ -n "${worktree_path}" ]] || continue
          statuses+=("$(rollout_inspect_target "${worktree_path}" "${inventory_json}")")
        done < <(printf '%s\n' "${inventory_json}" | jq -r '.worktrees[].path')
        ;;
      current)
        statuses+=("$(rollout_inspect_target "${repo_root}" "${inventory_json}")")
        ;;
      *)
        rollout_die "Unsupported rollout target scope: ${default_scope}"
        ;;
    esac
  else
    for worktree_path in "${target_worktrees[@]}"; do
      normalized_path="$(beads_resolve_normalize_path "${worktree_path}" "${repo_root}")"
      statuses+=("$(rollout_inspect_target "${normalized_path}" "${inventory_json}")")
    done
  fi

  rollout_json_array_from_objects "${statuses[@]}"
}

rollout_build_payload() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local stage="$4"
  local worktrees_json="$5"
  local effective_package_id="${6:-}"
  local manifest_path=""

  if [[ -n "${effective_package_id}" ]]; then
    manifest_path="$(rollout_manifest_path "${repo_root}" "${effective_package_id}")"
  fi

  jq -S -n \
    --arg schema "${ROLLOUT_SCHEMA}" \
    --arg repo_root "${repo_root}" \
    --arg canonical_root "${canonical_root}" \
    --arg stage "${stage}" \
    --arg package_id "${effective_package_id}" \
    --arg manifest_path "${manifest_path}" \
    --argjson inventory "${inventory_json}" \
    --argjson worktrees "${worktrees_json}" \
    '{
      schema: $schema,
      repo_root: $repo_root,
      canonical_root: $canonical_root,
      stage: $stage,
      package_id: (if $package_id == "" then null else $package_id end),
      rollback_manifest: (if $manifest_path == "" then null else $manifest_path end),
      inventory: {
        verdict: $inventory.summary.verdict,
        pilot_gate: $inventory.summary.pilot_gate
      },
      summary: {
        worktree_count: ($worktrees | length),
        ready_count: ([$worktrees[] | select(.rollout_stage == "ready")] | length),
        pilot_count: ([$worktrees[] | select(.rollout_stage == "pilot")] | length),
        cutover_count: ([$worktrees[] | select(.rollout_stage == "cutover")] | length),
        blocked_count: ([$worktrees[] | select(.blocking)] | length),
        rolled_back_count: ([$worktrees[] | select(.rollout_stage == "rolled-back")] | length)
      },
      worktrees: $worktrees
    }'
}

rollout_render_human() {
  local payload="$1"

  printf '%s\n' "${payload}" | jq -r '
    [
      "Schema: \(.schema)",
      "Repo Root: \(.repo_root)",
      "Canonical Root: \(.canonical_root)",
      "Stage: \(.stage)",
      "Inventory Verdict: \(.inventory.verdict)",
      "Pilot Gate: \(.inventory.pilot_gate)",
      (if .package_id == null then empty else "Rollback Package: \(.package_id)" end),
      (if .rollback_manifest == null then empty else "Rollback Manifest: \(.rollback_manifest)" end),
      "Worktrees: \(.summary.worktree_count)",
      "Ready: \(.summary.ready_count)",
      "Pilot: \(.summary.pilot_count)",
      "Cutover: \(.summary.cutover_count)",
      "Blocked: \(.summary.blocked_count)",
      "Rolled Back: \(.summary.rolled_back_count)",
      "",
      "Targets:",
      (if (.worktrees | length) == 0 then "  - none" else (.worktrees[] | "  - \(.path) (\(.branch)) stage=\(.rollout_stage) eligible=\(.eligible_for_cutover) blocking=\(.blocking) :: \(.reason)") end)
    ] | .[]'
}

rollout_render_env() {
  local payload="$1"

  printf '%s\n' "${payload}" | jq -r '
    [
      "schema=\(.schema)",
      "repo_root=\(.repo_root | @sh)",
      "canonical_root=\(.canonical_root | @sh)",
      "stage=\(.stage)",
      "package_id=\((.package_id // "") | @sh)",
      "worktree_count=\(.summary.worktree_count)",
      "ready_count=\(.summary.ready_count)",
      "pilot_count=\(.summary.pilot_count)",
      "cutover_count=\(.summary.cutover_count)",
      "blocked_count=\(.summary.blocked_count)",
      "rolled_back_count=\(.summary.rolled_back_count)"
    ] | .[]'
}

rollout_emit_payload() {
  local payload="$1"

  case "${output_format}" in
    human)
      rollout_render_human "${payload}"
      ;;
    json)
      printf '%s\n' "${payload}"
      ;;
    env)
      rollout_render_env "${payload}"
      ;;
  esac
}

rollout_target_key() {
  local index="$1"
  local branch_name="$2"
  local worktree_path="$3"
  local sanitized=""

  sanitized="$(printf '%s' "${branch_name:-$(basename "${worktree_path}")}" | tr '/:' '--' | tr -cd '[:alnum:]._-')"
  if [[ -z "${sanitized}" ]]; then
    sanitized="worktree"
  fi
  printf '%02d-%s\n' "${index}" "${sanitized}"
}

rollout_snapshot_target() {
  local worktree_path="$1"
  local branch_name="$2"
  local repo_root="$3"
  local effective_package_id="$4"
  local target_index="$5"
  local target_key=""
  local package_dir=""
  local target_snapshot_dir=""
  local relpath=""
  local abs_path=""
  local snapshot_path=""
  local existed="false"
  local -a files=()
  local -a snapshot_targets=(
    ".beads/config.yaml"
    ".beads/issues.jsonl"
    ".beads/beads.db"
    ".beads/redirect"
    ".beads/pilot-mode.json"
    ".beads/cutover-mode.json"
    ".beads/rollback-state.json"
  )

  package_dir="$(rollout_package_dir "${repo_root}" "${effective_package_id}")"
  target_key="$(rollout_target_key "${target_index}" "${branch_name}" "${worktree_path}")"
  target_snapshot_dir="${package_dir}/${target_key}"

  for relpath in "${snapshot_targets[@]}"; do
    abs_path="${worktree_path}/${relpath}"
    snapshot_path="${target_snapshot_dir}/${relpath}"
    existed="false"
    if [[ -f "${abs_path}" ]]; then
      mkdir -p "$(dirname "${snapshot_path}")"
      cp -p "${abs_path}" "${snapshot_path}"
      existed="true"
    fi

    files+=("$(
      jq -nc \
        --arg relpath "${relpath}" \
        --arg source_path "${abs_path}" \
        --arg snapshot_path "${snapshot_path}" \
        --argjson existed "${existed}" \
        '{
          relpath: $relpath,
          source_path: $source_path,
          snapshot_path: (if $existed then $snapshot_path else null end),
          existed: $existed
        }'
    )")
  done

  jq -nc \
    --arg path "${worktree_path}" \
    --arg branch "${branch_name}" \
    --arg snapshot_dir "${target_snapshot_dir}" \
    --argjson files "$(rollout_json_array_from_objects "${files[@]}")" \
    '{
      path: $path,
      branch: $branch,
      snapshot_dir: $snapshot_dir,
      files: $files
    }'
}

rollout_write_manifest() {
  local repo_root="$1"
  local canonical_root="$2"
  local effective_package_id="$3"
  local targets_json="$4"
  local manifest_path=""
  local snapshot_paths=""

  manifest_path="$(rollout_manifest_path "${repo_root}" "${effective_package_id}")"
  mkdir -p "$(dirname "${manifest_path}")"
  snapshot_paths="$(printf '%s\n' "${targets_json}" | jq '[.[] | .snapshot_dir]')"

  jq -S -n \
    --arg schema "${ROLLOUT_SCHEMA}" \
    --arg package_id "${effective_package_id}" \
    --arg repo_root "${repo_root}" \
    --arg canonical_root "${canonical_root}" \
    --arg jsonl_role "${ROLLOUT_JSONL_ROLE}" \
    --arg rollback_command "./scripts/beads-dolt-rollout.sh rollback --package-id ${effective_package_id}" \
    --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson targets "${targets_json}" \
    --argjson snapshot_paths "${snapshot_paths}" \
    '{
      schema: $schema,
      package_id: $package_id,
      repo_root: $repo_root,
      canonical_root: $canonical_root,
      created_at: $created_at,
      jsonl_role: $jsonl_role,
      rollback_command: $rollback_command,
      restores_operator_flow: true,
      restores_worktree_statuses: true,
      evidence_retained: true,
      snapshot_paths: $snapshot_paths,
      targets: $targets
    }' > "${manifest_path}"
}

rollout_write_cutover_mode_file() {
  local worktree_path="$1"
  local canonical_root="$2"
  local effective_package_id="$3"
  local source_stage="$4"
  local cutover_mode_file=""

  cutover_mode_file="$(rollout_cutover_mode_file "${worktree_path}")"
  mkdir -p "$(dirname "${cutover_mode_file}")"
  jq -S -n \
    --arg schema "${ROLLOUT_SCHEMA}" \
    --arg repo_root "${worktree_path}" \
    --arg canonical_root "${canonical_root}" \
    --arg source_stage "${source_stage}" \
    --arg jsonl_role "${ROLLOUT_JSONL_ROLE}" \
    --arg package_id "${effective_package_id}" \
    --arg review_command "./scripts/beads-dolt-rollout.sh verify --worktree ." \
    --arg rollback_command "./scripts/beads-dolt-rollout.sh rollback --package-id ${effective_package_id}" \
    '{
      schema: $schema,
      mode: "cutover",
      enabled: true,
      repo_root: $repo_root,
      canonical_root: $canonical_root,
      source_stage: $source_stage,
      jsonl_role: $jsonl_role,
      blocked_legacy_commands: ["sync"],
      review_command: $review_command,
      rollback_package_id: $package_id,
      rollback_command: $rollback_command
    }' > "${cutover_mode_file}"
}

rollout_update_manifest_after_rollback() {
  local repo_root="$1"
  local effective_package_id="$2"
  local rollback_results_json="$3"
  local manifest_path=""
  local temp_path=""

  manifest_path="$(rollout_manifest_path "${repo_root}" "${effective_package_id}")"
  temp_path="${manifest_path}.tmp"
  jq \
    --arg rolled_back_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson rollback_results "${rollback_results_json}" \
    '.rolled_back_at = $rolled_back_at | .rollback_results = $rollback_results' \
    "${manifest_path}" > "${temp_path}"
  mv "${temp_path}" "${manifest_path}"
}

rollout_restore_target() {
  local target_json="$1"
  local effective_package_id="$2"
  local worktree_path=""
  local relpath=""
  local source_path=""
  local existed=""

  worktree_path="$(printf '%s\n' "${target_json}" | jq -r '.path')"

  while IFS= read -r relpath; do
    source_path="$(printf '%s\n' "${target_json}" | jq -r --arg relpath "${relpath}" '.files[] | select(.relpath == $relpath) | .snapshot_path // ""')"
    existed="$(printf '%s\n' "${target_json}" | jq -r --arg relpath "${relpath}" '.files[] | select(.relpath == $relpath) | .existed')"

    if [[ "${existed}" == "true" ]]; then
      mkdir -p "$(dirname "${worktree_path}/${relpath}")"
      cp -p "${source_path}" "${worktree_path}/${relpath}"
    else
      rm -f "${worktree_path}/${relpath}"
    fi
  done < <(printf '%s\n' "${target_json}" | jq -r '.files[].relpath')

  mkdir -p "${worktree_path}/.beads"
  jq -S -n \
    --arg schema "${ROLLOUT_SCHEMA}" \
    --arg package_id "${effective_package_id}" \
    --arg restored_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      schema: $schema,
      mode: "rolled-back",
      package_id: $package_id,
      restored_at: $restored_at
    }' > "$(rollout_rollback_state_file "${worktree_path}")"
}

rollout_probe_legacy_sync() {
  local worktree_path="$1"
  local output=""
  local rc=""

  output="$(
    set +e
    (
      cd "${worktree_path}"
      bd sync
    ) 2>&1
    printf '\n__RC__=%s\n' "$?"
  )"
  rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"
  output="$(printf '%s\n' "${output}" | sed '/^__RC__=/d')"

  jq -nc \
    --arg output "${output}" \
    --argjson rc "${rc:-1}" \
    '{
      rc: $rc,
      output: $output
    }'
}

rollout_verify_target() {
  local target_json="$1"
  local worktree_path=""
  local branch_name=""
  local sync_probe=""
  local verified="true"
  local reason="This worktree satisfies the cutover verification contract."

  worktree_path="$(printf '%s\n' "${target_json}" | jq -r '.path')"
  branch_name="$(printf '%s\n' "${target_json}" | jq -r '.branch')"
  sync_probe="$(rollout_probe_legacy_sync "${worktree_path}")"

  if [[ "$(printf '%s\n' "${target_json}" | jq -r '.cutover_mode_enabled')" != "true" ]]; then
    verified="false"
    reason="Cutover mode is not enabled for this worktree."
  elif [[ "$(printf '%s\n' "${target_json}" | jq -r '.pilot_mode_enabled')" == "true" ]]; then
    verified="false"
    reason="Pilot and cutover markers must not coexist in the same worktree."
  elif [[ "$(printf '%s\n' "${target_json}" | jq -r '.issues_present')" == "true" ]]; then
    verified="false"
    reason="Tracked .beads/issues.jsonl reappeared inside a cutover worktree, which would recreate mixed mode."
  elif [[ "$(printf '%s\n' "${target_json}" | jq -r '.redirect_present')" == "true" ]]; then
    verified="false"
    reason="Redirect residue is still present in the cutover worktree."
  elif [[ "$(printf '%s\n' "${target_json}" | jq -r '.config_present')" != "true" || "$(printf '%s\n' "${target_json}" | jq -r '.db_present')" != "true" ]]; then
    verified="false"
    reason="Cutover requires a local config/database foundation in every target worktree."
  elif [[ "$(printf '%s\n' "${sync_probe}" | jq -r '.rc')" == "0" ]]; then
    verified="false"
    reason="Legacy sync still succeeded in a cutover worktree, so mixed-mode protection is not active."
  fi

  jq -nc \
    --arg path "${worktree_path}" \
    --arg branch "${branch_name}" \
    --arg reason "${reason}" \
    --argjson verified "${verified}" \
    --argjson sync_probe "${sync_probe}" \
    '{
      path: $path,
      branch: $branch,
      verified: $verified,
      reason: $reason,
      legacy_sync_probe: $sync_probe
    }'
}

rollout_status_like() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local scope="$4"
  local worktrees_json=""

  worktrees_json="$(rollout_collect_targets "${repo_root}" "${inventory_json}" "${scope}")"
  rollout_emit_payload "$(rollout_build_payload "${repo_root}" "${canonical_root}" "${inventory_json}" "report-only" "${worktrees_json}")"
}

rollout_cutover() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local worktrees_json=""
  local target_json=""
  local path=""
  local branch_name=""
  local stage_name=""
  local effective_package_id=""
  local blocked_count=0
  local target_index=0
  local eligible_count=0
  local -a post_targets=()
  local -a eligible_targets=()
  local -a snapshot_targets=()

  worktrees_json="$(rollout_collect_targets "${repo_root}" "${inventory_json}" "current")"
  while IFS= read -r target_json; do
    [[ -n "${target_json}" ]] || continue
    if [[ "$(printf '%s\n' "${target_json}" | jq -r '.eligible_for_cutover')" == "true" ]]; then
      eligible_targets+=("${target_json}")
      eligible_count=$((eligible_count + 1))
    elif [[ "$(printf '%s\n' "${target_json}" | jq -r '.cutover_mode_enabled')" != "true" ]]; then
      blocked_count=$((blocked_count + 1))
    fi
  done < <(printf '%s\n' "${worktrees_json}" | jq -c '.[]')

  if [[ "${eligible_count}" -gt 0 ]]; then
    effective_package_id="${package_id:-rollout-$(date -u +%Y%m%dT%H%M%SZ)}"
    snapshot_targets=()
    target_index=0
    for target_json in "${eligible_targets[@]}"; do
      ((target_index += 1))
      path="$(printf '%s\n' "${target_json}" | jq -r '.path')"
      branch_name="$(printf '%s\n' "${target_json}" | jq -r '.branch')"
      snapshot_targets+=("$(rollout_snapshot_target "${path}" "${branch_name}" "${repo_root}" "${effective_package_id}" "${target_index}")")
    done
    rollout_write_manifest "${repo_root}" "${canonical_root}" "${effective_package_id}" "$(rollout_json_array_from_objects "${snapshot_targets[@]}")"
  fi

  while IFS= read -r target_json; do
    [[ -n "${target_json}" ]] || continue
    path="$(printf '%s\n' "${target_json}" | jq -r '.path')"
    stage_name="$(printf '%s\n' "${target_json}" | jq -r '.rollout_stage')"
    if [[ "$(printf '%s\n' "${target_json}" | jq -r '.eligible_for_cutover')" == "true" ]]; then
      rm -f "$(rollout_pilot_mode_file "${path}")" "$(rollout_rollback_state_file "${path}")"
      rollout_write_cutover_mode_file "${path}" "${canonical_root}" "${effective_package_id}" "${stage_name}"
    fi
    post_targets+=("$(rollout_inspect_target "${path}" "${inventory_json}")")
  done < <(printf '%s\n' "${worktrees_json}" | jq -c '.[]')

  rollout_emit_payload "$(rollout_build_payload "${repo_root}" "${canonical_root}" "${inventory_json}" "controlled-cutover" "$(rollout_json_array_from_objects "${post_targets[@]}")" "${effective_package_id}")"
  if [[ "${blocked_count}" -gt 0 ]]; then
    return 20
  fi
  return 0
}

rollout_verify() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local worktrees_json=""
  local target_json=""
  local verified_json=""
  local failed_count=0
  local -a verified_targets=()

  worktrees_json="$(rollout_collect_targets "${repo_root}" "${inventory_json}" "current")"
  while IFS= read -r target_json; do
    [[ -n "${target_json}" ]] || continue
    verified_json="$(rollout_verify_target "${target_json}")"
    if [[ "$(printf '%s\n' "${verified_json}" | jq -r '.verified')" != "true" ]]; then
      failed_count=$((failed_count + 1))
    fi
    verified_targets+=("$(
      jq -nc \
        --argjson target "${target_json}" \
        --argjson verification "${verified_json}" \
        '$target + {verification: $verification}'
    )")
  done < <(printf '%s\n' "${worktrees_json}" | jq -c '.[]')

  rollout_emit_payload "$(rollout_build_payload "${repo_root}" "${canonical_root}" "${inventory_json}" "verification" "$(rollout_json_array_from_objects "${verified_targets[@]}")")"
  if [[ "${failed_count}" -gt 0 ]]; then
    return 21
  fi
  return 0
}

rollout_rollback() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local effective_package_id="${package_id:-}"
  local manifest_path=""
  local target_json=""
  local target_path=""
  local rollback_results_json=""
  local -a rollback_results=()

  [[ -n "${effective_package_id}" ]] || rollout_die "rollback requires --package-id"
  manifest_path="$(rollout_manifest_path "${repo_root}" "${effective_package_id}")"
  [[ -f "${manifest_path}" ]] || rollout_die "Rollback package not found: ${manifest_path}"

  while IFS= read -r target_json; do
    [[ -n "${target_json}" ]] || continue
    target_path="$(printf '%s\n' "${target_json}" | jq -r '.path')"
    if [[ "${#target_worktrees[@]}" -gt 0 ]]; then
      if ! printf '%s\n' "${target_worktrees[@]}" | while IFS= read -r candidate_path; do beads_resolve_normalize_path "${candidate_path}" "${repo_root}"; done | grep -Fxq "${target_path}"; then
        continue
      fi
    fi
    rollout_restore_target "${target_json}" "${effective_package_id}"
    rollback_results+=("$(rollout_inspect_target "${target_path}" "${inventory_json}")")
  done < <(jq -c '.targets[]' "${manifest_path}")

  rollback_results_json="$(rollout_json_array_from_objects "${rollback_results[@]}")"
  rollout_update_manifest_after_rollback "${repo_root}" "${effective_package_id}" "${rollback_results_json}"
  rollout_emit_payload "$(rollout_build_payload "${repo_root}" "${canonical_root}" "${inventory_json}" "rollback" "${rollback_results_json}" "${effective_package_id}")"
}

main() {
  local repo_root=""
  local canonical_root=""
  local inventory_json=""

  rollout_parse_args "$@"
  repo_root="$(rollout_repo_root "${repo_override:-$PWD}")"
  canonical_root="$(rollout_canonical_root "${repo_root}")"
  inventory_json="$(rollout_inventory_json "${repo_root}")"

  case "${subcommand}" in
    status|report-only)
      rollout_status_like "${repo_root}" "${canonical_root}" "${inventory_json}" "all"
      ;;
    cutover)
      rollout_cutover "${repo_root}" "${canonical_root}" "${inventory_json}"
      ;;
    verify)
      rollout_verify "${repo_root}" "${canonical_root}" "${inventory_json}"
      ;;
    rollback)
      rollout_rollback "${repo_root}" "${canonical_root}" "${inventory_json}"
      ;;
    *)
      rollout_die "Unsupported subcommand: ${subcommand}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
