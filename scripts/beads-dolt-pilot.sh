#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/beads-resolve-db.sh
source "${REPO_ROOT}/scripts/beads-resolve-db.sh"

PILOT_SCHEMA="beads-dolt-pilot/v1"
subcommand="status"
repo_override=""
output_format="human"

pilot_usage() {
  cat <<'EOF'
Usage:
  scripts/beads-dolt-pilot.sh [status|enable|review] [--repo <path>] [--format <human|json|env>]

Description:
  Manage one isolated Beads pilot worktree without touching rollout. The pilot
  workflow is gated by the inventory/readiness report and exposes a deterministic
  review surface that does not treat tracked .beads/issues.jsonl as the primary
  operator interface.
EOF
}

pilot_die() {
  echo "[beads-dolt-pilot] $*" >&2
  exit 2
}

pilot_parse_args() {
  if [[ $# -gt 0 ]]; then
    case "${1}" in
      status|enable|review)
        subcommand="$1"
        shift
        ;;
      -h|--help)
        pilot_usage
        exit 0
        ;;
    esac
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo_override="${2:-}"
        [[ -n "${repo_override}" ]] || pilot_die "--repo requires a value"
        shift 2
        ;;
      --format)
        output_format="${2:-}"
        [[ -n "${output_format}" ]] || pilot_die "--format requires a value"
        shift 2
        ;;
      -h|--help)
        pilot_usage
        exit 0
        ;;
      *)
        pilot_die "Unknown argument: $1"
        ;;
    esac
  done

  case "${output_format}" in
    human|json|env) ;;
    *)
      pilot_die "Unsupported output format: ${output_format}"
      ;;
  esac
}

pilot_repo_root() {
  local probe_path="${1:-$PWD}"
  local repo_root=""

  repo_root="$(beads_resolve_repo_root "${probe_path}" 2>/dev/null || true)"
  [[ -n "${repo_root}" ]] || pilot_die "Could not determine repo root for ${probe_path}"
  printf '%s\n' "${repo_root}"
}

pilot_canonical_root() {
  local repo_root="$1"
  local canonical_root=""

  canonical_root="$(beads_resolve_canonical_root "${repo_root}" 2>/dev/null || true)"
  if [[ -z "${canonical_root}" ]]; then
    canonical_root="${repo_root}"
  fi
  printf '%s\n' "${canonical_root}"
}

pilot_mode_file() {
  local repo_root="$1"
  printf '%s/.beads/pilot-mode.json\n' "${repo_root}"
}

pilot_review_command() {
  printf './scripts/beads-dolt-pilot.sh review\n'
}

pilot_inventory_json() {
  local repo_root="$1"
  (
    cd "${repo_root}"
    "${SCRIPT_DIR}/beads-dolt-migration-inventory.sh" --format json
  )
}

pilot_mode_enabled() {
  local repo_root="$1"
  [[ -f "$(pilot_mode_file "${repo_root}")" ]]
}

pilot_write_mode_file() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local mode_file=""

  mode_file="$(pilot_mode_file "${repo_root}")"
  mkdir -p "$(dirname "${mode_file}")"
  jq -S -n \
    --arg schema "${PILOT_SCHEMA}" \
    --arg repo_root "${repo_root}" \
    --arg canonical_root "${canonical_root}" \
    --arg review_command "$(pilot_review_command)" \
    --arg inventory_verdict "$(printf '%s\n' "${inventory_json}" | jq -r '.summary.verdict')" \
    --arg pilot_gate "$(printf '%s\n' "${inventory_json}" | jq -r '.summary.pilot_gate')" \
    --arg full_cutover_gate "$(printf '%s\n' "${inventory_json}" | jq -r '.summary.full_cutover_gate')" \
    '{
      schema: $schema,
      mode: "pilot",
      enabled: true,
      repo_root: $repo_root,
      canonical_root: $canonical_root,
      blocked_legacy_commands: ["sync"],
      review_command: $review_command,
      inventory_verdict: $inventory_verdict,
      pilot_gate: $pilot_gate,
      full_cutover_gate: $full_cutover_gate
    }' > "${mode_file}"
}

pilot_capture_command_json() {
  local repo_root="$1"
  local label="$2"
  shift 2

  local output=""
  local rc=""

  output="$(
    set +e
    (
      cd "${repo_root}"
      "$@"
    ) 2>&1
    printf '\n__RC__=%s\n' "$?"
  )"
  rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"
  output="$(printf '%s\n' "${output}" | sed '/^__RC__=/d')"

  jq -nc \
    --arg label "${label}" \
    --arg command "$*" \
    --arg output "${output}" \
    --argjson rc "${rc:-1}" \
    '{
      label: $label,
      command: $command,
      rc: $rc,
      output: $output
    }'
}

pilot_capture_info_json() {
  local repo_root="$1"
  local info_json=""
  local info_rc=""

  info_json="$(pilot_capture_command_json "${repo_root}" "info" bd --no-daemon info)"
  info_rc="$(printf '%s\n' "${info_json}" | jq -r '.rc')"
  if [[ "${info_rc}" != "0" ]]; then
    info_json="$(pilot_capture_command_json "${repo_root}" "info" bd info)"
  fi

  printf '%s\n' "${info_json}"
}

pilot_build_status_json() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local enabled="$4"
  local mode_file=""

  mode_file="$(pilot_mode_file "${repo_root}")"
  jq -S -n \
    --arg schema "${PILOT_SCHEMA}" \
    --arg repo_root "${repo_root}" \
    --arg canonical_root "${canonical_root}" \
    --arg mode_file "${mode_file}" \
    --arg review_command "$(pilot_review_command)" \
    --arg inventory_verdict "$(printf '%s\n' "${inventory_json}" | jq -r '.summary.verdict')" \
    --arg pilot_gate "$(printf '%s\n' "${inventory_json}" | jq -r '.summary.pilot_gate')" \
    --arg full_cutover_gate "$(printf '%s\n' "${inventory_json}" | jq -r '.summary.full_cutover_gate')" \
    --argjson enabled "${enabled}" \
    '{
      schema: $schema,
      repo_root: $repo_root,
      canonical_root: $canonical_root,
      pilot_mode_enabled: $enabled,
      pilot_mode_file: $mode_file,
      review_command: $review_command,
      inventory_verdict: $inventory_verdict,
      pilot_gate: $pilot_gate,
      full_cutover_gate: $full_cutover_gate
    }'
}

pilot_build_review_json() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local enabled="$4"
  local info_json=""
  local ready_json=""
  local list_json=""

  info_json="$(pilot_capture_info_json "${repo_root}")"
  ready_json="$(pilot_capture_command_json "${repo_root}" "ready" bd ready)"
  list_json="$(pilot_capture_command_json "${repo_root}" "list_all" bd list --all)"

  jq -S -n \
    --arg schema "${PILOT_SCHEMA}" \
    --arg repo_root "${repo_root}" \
    --arg canonical_root "${canonical_root}" \
    --arg review_command "$(pilot_review_command)" \
    --argjson enabled "${enabled}" \
    --argjson inventory "${inventory_json}" \
    --argjson info "${info_json}" \
    --argjson ready "${ready_json}" \
    --argjson list_all "${list_json}" \
    '{
      schema: $schema,
      repo_root: $repo_root,
      canonical_root: $canonical_root,
      pilot_mode_enabled: $enabled,
      review_command: $review_command,
      inventory: {
        verdict: $inventory.summary.verdict,
        pilot_gate: $inventory.summary.pilot_gate,
        full_cutover_gate: $inventory.summary.full_cutover_gate,
        pilot_blocking_count: $inventory.summary.pilot_blocking_count,
        blocking_count: $inventory.summary.blocking_count,
        warning_count: $inventory.summary.warning_count
      },
      review_surface: {
        info: $info,
        ready: $ready,
        list_all: $list_all
      }
    }'
}

pilot_render_human() {
  local payload="$1"
  local payload_type="$2"

  case "${payload_type}" in
    status)
      printf '%s\n' "${payload}" | jq -r '
        [
          "Schema: \(.schema)",
          "Repo Root: \(.repo_root)",
          "Canonical Root: \(.canonical_root)",
          "Pilot Mode Enabled: \(.pilot_mode_enabled)",
          "Pilot Mode File: \(.pilot_mode_file)",
          "Inventory Verdict: \(.inventory_verdict)",
          "Pilot Gate: \(.pilot_gate)",
          "Full Cutover Gate: \(.full_cutover_gate)",
          "Review Command: \(.review_command)"
        ]
        | .[]'
      ;;
    review)
      printf '%s\n' "${payload}" | jq -r '
        [
          "Schema: \(.schema)",
          "Repo Root: \(.repo_root)",
          "Canonical Root: \(.canonical_root)",
          "Pilot Mode Enabled: \(.pilot_mode_enabled)",
          "Inventory Verdict: \(.inventory.verdict)",
          "Pilot Gate: \(.inventory.pilot_gate)",
          "Full Cutover Gate: \(.inventory.full_cutover_gate)",
          "Pilot Blocking Items: \(.inventory.pilot_blocking_count)",
          "Full Cutover Blocking Items: \(.inventory.blocking_count)",
          "Review Command: \(.review_command)",
          "",
          "Review Surface:",
          "--- info ---",
          (.review_surface.info.output // ""),
          "",
          "--- ready ---",
          (.review_surface.ready.output // ""),
          "",
          "--- list --all ---",
          (.review_surface.list_all.output // "")
        ]
        | .[]'
      ;;
    *)
      pilot_die "Unsupported payload type for human rendering: ${payload_type}"
      ;;
  esac
}

pilot_render_env() {
  local payload="$1"
  local payload_type="$2"

  case "${payload_type}" in
    status)
      printf '%s\n' "${payload}" | jq -r '
        [
          "schema=\(.schema)",
          "repo_root=\(.repo_root | @sh)",
          "canonical_root=\(.canonical_root | @sh)",
          "pilot_mode_enabled=\(.pilot_mode_enabled)",
          "pilot_mode_file=\(.pilot_mode_file | @sh)",
          "inventory_verdict=\(.inventory_verdict)",
          "pilot_gate=\(.pilot_gate)",
          "full_cutover_gate=\(.full_cutover_gate)",
          "review_command=\(.review_command | @sh)"
        ]
        | .[]'
      ;;
    review)
      printf '%s\n' "${payload}" | jq -r '
        [
          "schema=\(.schema)",
          "repo_root=\(.repo_root | @sh)",
          "canonical_root=\(.canonical_root | @sh)",
          "pilot_mode_enabled=\(.pilot_mode_enabled)",
          "inventory_verdict=\(.inventory.verdict)",
          "pilot_gate=\(.inventory.pilot_gate)",
          "full_cutover_gate=\(.inventory.full_cutover_gate)",
          "pilot_blocking_count=\(.inventory.pilot_blocking_count)",
          "full_cutover_blocking_count=\(.inventory.blocking_count)",
          "review_command=\(.review_command | @sh)",
          "info_rc=\(.review_surface.info.rc)",
          "ready_rc=\(.review_surface.ready.rc)",
          "list_all_rc=\(.review_surface.list_all.rc)"
        ]
        | .[]'
      ;;
    *)
      pilot_die "Unsupported payload type for env rendering: ${payload_type}"
      ;;
  esac
}

pilot_emit_payload() {
  local payload="$1"
  local payload_type="$2"

  case "${output_format}" in
    human)
      pilot_render_human "${payload}" "${payload_type}"
      ;;
    json)
      printf '%s\n' "${payload}"
      ;;
    env)
      pilot_render_env "${payload}" "${payload_type}"
      ;;
  esac
}

pilot_status() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local enabled="false"

  if pilot_mode_enabled "${repo_root}"; then
    enabled="true"
  fi

  pilot_emit_payload \
    "$(pilot_build_status_json "${repo_root}" "${canonical_root}" "${inventory_json}" "${enabled}")" \
    "status"
}

pilot_enable() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local gate_status=""

  gate_status="$(printf '%s\n' "${inventory_json}" | jq -r '.summary.pilot_gate')"
  if [[ "${repo_root}" == "${canonical_root}" ]]; then
    printf 'Pilot mode is only supported in an isolated dedicated worktree, not the canonical root.\n' >&2
    return 21
  fi
  if [[ "${gate_status}" != "pass" ]]; then
    printf 'Pilot readiness gate is blocked for %s.\n' "${repo_root}" >&2
    printf 'Run: ./scripts/beads-dolt-migration-inventory.sh\n' >&2
    return 20
  fi

  pilot_write_mode_file "${repo_root}" "${canonical_root}" "${inventory_json}"
  pilot_status "${repo_root}" "${canonical_root}" "${inventory_json}"
  return 0
}

pilot_review() {
  local repo_root="$1"
  local canonical_root="$2"
  local inventory_json="$3"
  local enabled="false"

  if ! pilot_mode_enabled "${repo_root}"; then
    printf 'Pilot mode is not enabled in %s.\n' "${repo_root}" >&2
    printf 'Run: ./scripts/beads-dolt-pilot.sh enable\n' >&2
    return 22
  fi
  enabled="true"

  pilot_emit_payload \
    "$(pilot_build_review_json "${repo_root}" "${canonical_root}" "${inventory_json}" "${enabled}")" \
    "review"
}

main() {
  local repo_root=""
  local canonical_root=""
  local inventory_json=""

  pilot_parse_args "$@"
  repo_root="$(pilot_repo_root "${repo_override:-$PWD}")"
  canonical_root="$(pilot_canonical_root "${repo_root}")"
  inventory_json="$(pilot_inventory_json "${repo_root}")"

  case "${subcommand}" in
    status)
      pilot_status "${repo_root}" "${canonical_root}" "${inventory_json}"
      ;;
    enable)
      pilot_enable "${repo_root}" "${canonical_root}" "${inventory_json}"
      ;;
    review)
      pilot_review "${repo_root}" "${canonical_root}" "${inventory_json}"
      ;;
    *)
      pilot_die "Unsupported subcommand: ${subcommand}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
