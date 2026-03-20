#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib/test_helpers.sh"
source "${SCRIPT_DIR}/../lib/git_topology_fixture.sh"

seed_real_pilot_tools() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/bin" "${repo_dir}/scripts" "${repo_dir}/.githooks"
    cp "${PROJECT_ROOT}/bin/bd" "${repo_dir}/bin/bd"
    cp "${PROJECT_ROOT}/scripts/beads-resolve-db.sh" "${repo_dir}/scripts/beads-resolve-db.sh"
    cp "${PROJECT_ROOT}/scripts/beads-dolt-migration-inventory.sh" "${repo_dir}/scripts/beads-dolt-migration-inventory.sh"
    cp "${PROJECT_ROOT}/scripts/beads-dolt-pilot.sh" "${repo_dir}/scripts/beads-dolt-pilot.sh"
    cp "${PROJECT_ROOT}/scripts/beads-normalize-issues-jsonl.sh" "${repo_dir}/scripts/beads-normalize-issues-jsonl.sh"
    cp "${PROJECT_ROOT}/scripts/beads-worktree-audit.sh" "${repo_dir}/scripts/beads-worktree-audit.sh"
    cp "${PROJECT_ROOT}/scripts/beads-worktree-localize.sh" "${repo_dir}/scripts/beads-worktree-localize.sh"
    cp "${PROJECT_ROOT}/.githooks/pre-commit" "${repo_dir}/.githooks/pre-commit"
    cp "${PROJECT_ROOT}/.githooks/_repo-local-path.sh" "${repo_dir}/.githooks/_repo-local-path.sh"
    chmod +x \
        "${repo_dir}/bin/bd" \
        "${repo_dir}/scripts/beads-resolve-db.sh" \
        "${repo_dir}/scripts/beads-dolt-migration-inventory.sh" \
        "${repo_dir}/scripts/beads-dolt-pilot.sh" \
        "${repo_dir}/scripts/beads-normalize-issues-jsonl.sh" \
        "${repo_dir}/scripts/beads-worktree-audit.sh" \
        "${repo_dir}/scripts/beads-worktree-localize.sh" \
        "${repo_dir}/.githooks/pre-commit" \
        "${repo_dir}/.githooks/_repo-local-path.sh"
}

commit_fixture_state() {
    local repo_dir="$1"
    local message="$2"

    (
        cd "${repo_dir}"
        git add -A
        git commit -m "${message}" >/dev/null
    )
}

create_fake_pilot_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/pilot-fake-bd-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${FAKE_BD_MODE:-legacy}"
db_path=""
readonly_flag="false"
args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)
      db_path="${2:-}"
      shift 2
      ;;
    --db=*)
      db_path="${1#--db=}"
      shift
      ;;
    --no-daemon)
      readonly_flag="true"
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

cwd="$(pwd -P)"
repo_root="$(git -C "${cwd}" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "${cwd}")"
canonical_root="$(cd "${repo_root}" && cd "$(git rev-parse --git-common-dir)/.." && pwd -P)"

case "${args[*]}" in
  "--version")
    printf 'bd version 0.49.6 (pilot-fixture)\n'
    exit 0
    ;;
  "info")
    if [[ "${mode}" == "modern" && "${readonly_flag}" == "true" ]]; then
      printf 'Error: unknown flag: --no-daemon\n' >&2
      exit 1
    fi
    cat <<EOT
Beads Database Information
===========================
Database: ${db_path:-${repo_root}/.beads/beads.db}
Mode: direct

Daemon Status:
  Connected: no
  Reason: $( [[ "${readonly_flag}" == "true" ]] && printf 'flag_no_daemon' || printf 'worktree_safety' )
EOT
    exit 0
    ;;
  "backend show")
    case "${mode}" in
      legacy)
        cat <<EOT
Current backend: sqlite
  Description: SQLite database
  Beads dir: ${canonical_root}/.beads
  Database: ${canonical_root}/.beads/beads.db
EOT
        ;;
      pilot-ready)
        cat <<EOT
Current backend: dolt
  Description: Dolt backend
  Beads dir: ${repo_root}/.beads
  Database: ${repo_root}/.beads/beads.db
EOT
        ;;
      *)
        exit 1
        ;;
    esac
    exit 0
    ;;
  "ready")
    printf 'fixture ready\n'
    exit 0
    ;;
  "list --all")
    printf 'fixture list --all\n'
    exit 0
    ;;
  "sync")
    printf 'fixture sync\n'
    exit 0
    ;;
  *)
    printf 'fixture command: %s\n' "${args[*]}"
    exit 0
    ;;
esac
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

run_pilot_script() {
    local repo_dir="$1"
    local fake_bin="$2"
    local fake_mode="$3"
    shift 3

    (
        cd "${repo_dir}"
        PATH="${repo_dir}/bin:${fake_bin}:$PATH" \
        BEADS_SYSTEM_BD="${fake_bin}/bd" \
        FAKE_BD_MODE="${fake_mode}" \
        ./scripts/beads-dolt-pilot.sh "$@"
    )
}

run_plain_bd() {
    local repo_dir="$1"
    local fake_bin="$2"
    local fake_mode="$3"
    shift 3

    (
        cd "${repo_dir}"
        PATH="${repo_dir}/bin:${fake_bin}:$PATH" \
        BEADS_SYSTEM_BD="${fake_bin}/bd" \
        FAKE_BD_MODE="${fake_mode}" \
        bd "$@"
    )
}

run_pre_commit() {
    local repo_dir="$1"
    local fake_bin="$2"
    local fake_mode="$3"

    (
        cd "${repo_dir}"
        PATH="${repo_dir}/bin:${fake_bin}:$PATH" \
        BEADS_SYSTEM_BD="${fake_bin}/bd" \
        FAKE_BD_MODE="${fake_mode}" \
        ./.githooks/pre-commit
    )
}

create_isolated_pilot_worktree_fixture() {
    local fixture_root="$1"
    local layout_mode="$2"
    local seed_mode="$3"
    local commit_message="$4"
    local repo_dir worktree_dir

    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    git_topology_fixture_seed_beads_migration_surface_layout "${repo_dir}" "${layout_mode}"
    case "${seed_mode}" in
        legacy-jsonl-first)
            git_topology_fixture_seed_legacy_jsonl_first_state "${repo_dir}"
            ;;
        pilot-ready)
            git_topology_fixture_seed_pilot_ready_state "${repo_dir}"
            ;;
        *)
            printf 'unsupported seed mode: %s\n' "${seed_mode}" >&2
            return 1
            ;;
    esac
    seed_real_pilot_tools "${repo_dir}"
    commit_fixture_state "${repo_dir}" "${commit_message}"

    worktree_dir="${fixture_root}/pilot-worktree"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_dir}" "feat/pilot" "main"

    printf '%s\n%s\n' "${repo_dir}" "${worktree_dir}"
}

create_blocked_sibling_worktree() {
    local repo_dir="$1"
    local sibling_path="$2"

    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${sibling_path}" "feat/blocked" "main"
    git_topology_fixture_seed_legacy_jsonl_first_state "${sibling_path}"
}

test_pilot_enable_blocks_when_inventory_gate_is_blocked() {
    test_start "pilot_enable_blocks_when_inventory_gate_is_blocked"

    local fixture_root repo_dir worktree_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-dolt-pilot.XXXXXX)"
    mapfile -t fixture_paths < <(
        create_isolated_pilot_worktree_fixture \
            "${fixture_root}" \
            legacy \
            legacy-jsonl-first \
            "fixture: seed blocked pilot state"
    )
    repo_dir="${fixture_paths[0]}"
    worktree_dir="${fixture_paths[1]}"
    fake_bin="$(create_fake_pilot_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_pilot_script "${worktree_dir}" "${fake_bin}" legacy enable 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "20" "${rc}" "Pilot enable must stop on a blocked readiness gate"
    assert_contains "${output}" "Pilot readiness gate is blocked" "Blocked pilot enable must explain why it refused to arm"

    rm -rf "${fixture_root}"
    test_pass
}

test_pilot_enable_ignores_blocked_siblings_when_current_worktree_is_ready() {
    test_start "pilot_enable_ignores_blocked_siblings_when_current_worktree_is_ready"

    local fixture_root repo_dir worktree_dir blocked_sibling fake_bin status_json
    fixture_root="$(mktemp -d /tmp/beads-dolt-pilot.XXXXXX)"
    mapfile -t fixture_paths < <(
        create_isolated_pilot_worktree_fixture \
            "${fixture_root}" \
            pilot-ready \
            pilot-ready \
            "fixture: seed pilot-ready state with blocked sibling"
    )
    repo_dir="${fixture_paths[0]}"
    worktree_dir="${fixture_paths[1]}"
    blocked_sibling="${fixture_root}/blocked-sibling"
    create_blocked_sibling_worktree "${repo_dir}" "${blocked_sibling}"
    fake_bin="$(create_fake_pilot_bd_bin "${fixture_root}")"

    run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready enable >/dev/null
    status_json="$(run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready status --format json)"

    assert_json_value "${status_json}" '.pilot_mode_enabled' "true" "Pilot enable must still arm the isolated ready worktree"
    assert_json_value "${status_json}" '.pilot_gate' "pass" "Pilot gate must stay passed for the current worktree"
    assert_json_value "${status_json}" '.full_cutover_gate' "blocked" "Pilot status must still expose fleet-wide blockers"

    rm -rf "${fixture_root}"
    test_pass
}

test_pilot_enable_writes_mode_file_when_gate_passes() {
    test_start "pilot_enable_writes_mode_file_when_gate_passes"

    local fixture_root repo_dir worktree_dir fake_bin status_json mode_file
    fixture_root="$(mktemp -d /tmp/beads-dolt-pilot.XXXXXX)"
    mapfile -t fixture_paths < <(
        create_isolated_pilot_worktree_fixture \
            "${fixture_root}" \
            pilot-ready \
            pilot-ready \
            "fixture: seed ready pilot state"
    )
    repo_dir="${fixture_paths[0]}"
    worktree_dir="${fixture_paths[1]}"
    fake_bin="$(create_fake_pilot_bd_bin "${fixture_root}")"

    run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready enable >/dev/null
    status_json="$(run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready status --format json)"
    mode_file="${worktree_dir}/.beads/pilot-mode.json"

    assert_file_exists "${mode_file}" "Pilot enable must materialize the pilot mode marker"
    assert_json_value "${status_json}" '.pilot_mode_enabled' "true" "Pilot status must report the pilot mode marker as enabled"
    assert_json_value "${status_json}" '.pilot_gate' "pass" "Pilot status must preserve the passed pilot gate"

    rm -rf "${fixture_root}"
    test_pass
}

test_pilot_review_emits_review_surface() {
    test_start "pilot_review_emits_review_surface"

    local fixture_root repo_dir worktree_dir fake_bin review_json
    fixture_root="$(mktemp -d /tmp/beads-dolt-pilot.XXXXXX)"
    mapfile -t fixture_paths < <(
        create_isolated_pilot_worktree_fixture \
            "${fixture_root}" \
            pilot-ready \
            pilot-ready \
            "fixture: seed review pilot state"
    )
    repo_dir="${fixture_paths[0]}"
    worktree_dir="${fixture_paths[1]}"
    fake_bin="$(create_fake_pilot_bd_bin "${fixture_root}")"

    run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready enable >/dev/null
    review_json="$(run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready review --format json)"

    assert_json_value "${review_json}" '.pilot_mode_enabled' "true" "Pilot review must require enabled pilot mode"
    assert_json_value "${review_json}" '.inventory.pilot_gate' "pass" "Pilot review must preserve the passed gate"
    assert_json_value "${review_json}" '.review_surface.info.rc' "0" "Pilot review must capture read-only info successfully"
    assert_json_value "${review_json}" '.review_surface.ready.rc' "0" "Pilot review must capture ready output successfully"
    assert_json_value "${review_json}" '.review_surface.list_all.rc' "0" "Pilot review must capture list output successfully"
    assert_contains "${review_json}" "fixture ready" "Pilot review must include the ready output in the review surface"
    assert_contains "${review_json}" "fixture list --all" "Pilot review must include the list output in the review surface"

    rm -rf "${fixture_root}"
    test_pass
}

test_pilot_review_falls_back_to_bd_info_for_modern_cli() {
    test_start "pilot_review_falls_back_to_bd_info_for_modern_cli"

    local fixture_root repo_dir worktree_dir fake_bin review_json
    fixture_root="$(mktemp -d /tmp/beads-dolt-pilot.XXXXXX)"
    mapfile -t fixture_paths < <(
        create_isolated_pilot_worktree_fixture \
            "${fixture_root}" \
            pilot-ready \
            pilot-ready \
            "fixture: seed ready pilot state for modern cli"
    )
    repo_dir="${fixture_paths[0]}"
    worktree_dir="${fixture_paths[1]}"
    fake_bin="$(create_fake_pilot_bd_bin "${fixture_root}")"

    run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready enable >/dev/null
    review_json="$(run_pilot_script "${worktree_dir}" "${fake_bin}" modern review --format json)"

    assert_json_value "${review_json}" '.review_surface.info.rc' "0" "Pilot review must fall back to bd info when --no-daemon is unsupported"
    assert_json_value "${review_json}" '.review_surface.info.command' "bd info" "Pilot review must record the modern fallback command"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_sync_when_pilot_mode_is_enabled() {
    test_start "plain_bd_blocks_sync_when_pilot_mode_is_enabled"

    local fixture_root repo_dir worktree_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-dolt-pilot.XXXXXX)"
    mapfile -t fixture_paths < <(
        create_isolated_pilot_worktree_fixture \
            "${fixture_root}" \
            pilot-ready \
            pilot-ready \
            "fixture: seed sync-block pilot state"
    )
    repo_dir="${fixture_paths[0]}"
    worktree_dir="${fixture_paths[1]}"
    fake_bin="$(create_fake_pilot_bd_bin "${fixture_root}")"

    run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready enable >/dev/null
    output="$(
        set +e
        run_plain_bd "${worktree_dir}" "${fake_bin}" pilot-ready sync 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "27" "${rc}" "Plain bd must fail closed on legacy-only sync while pilot mode is enabled"
    assert_contains "${output}" "pilot mode is enabled" "Pilot sync block must explain the mode-specific failure"
    assert_contains "${output}" "beads-dolt-pilot.sh review" "Pilot sync block must point to the review surface"

    rm -rf "${fixture_root}"
    test_pass
}

test_pre_commit_blocks_staged_jsonl_in_pilot_mode() {
    test_start "pre_commit_blocks_staged_jsonl_in_pilot_mode"

    local fixture_root repo_dir worktree_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-dolt-pilot.XXXXXX)"
    mapfile -t fixture_paths < <(
        create_isolated_pilot_worktree_fixture \
            "${fixture_root}" \
            pilot-ready \
            pilot-ready \
            "fixture: seed pre-commit pilot state"
    )
    repo_dir="${fixture_paths[0]}"
    worktree_dir="${fixture_paths[1]}"
    fake_bin="$(create_fake_pilot_bd_bin "${fixture_root}")"

    run_pilot_script "${worktree_dir}" "${fake_bin}" pilot-ready enable >/dev/null
    cat > "${worktree_dir}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"pilot-jsonl","status":"open","type":"task","priority":3}
EOF
    (
        cd "${worktree_dir}"
        git add .beads/issues.jsonl
    )

    output="$(
        set +e
        run_pre_commit "${worktree_dir}" "${fake_bin}" pilot-ready 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "1" "${rc}" "Pre-commit must block staged issues.jsonl while pilot mode is enabled"
    assert_contains "${output}" "Pilot mode blocks staged .beads/issues.jsonl" "Pre-commit must explain the pilot JSONL block"
    assert_contains "${output}" "beads-dolt-pilot.sh review" "Pre-commit must point operators to the review surface"

    rm -rf "${fixture_root}"
    test_pass
}

test_pilot_enable_rejects_canonical_root() {
    test_start "pilot_enable_rejects_canonical_root"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-dolt-pilot.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    git_topology_fixture_seed_beads_migration_surface_layout "${repo_dir}" pilot-ready
    git_topology_fixture_seed_pilot_ready_state "${repo_dir}"
    seed_real_pilot_tools "${repo_dir}"
    commit_fixture_state "${repo_dir}" "fixture: seed canonical-root rejection"
    fake_bin="$(create_fake_pilot_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_pilot_script "${repo_dir}" "${fake_bin}" pilot-ready enable 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "21" "${rc}" "Pilot enable must reject the canonical root even when readiness passes"
    assert_contains "${output}" "isolated dedicated worktree" "Canonical-root rejection must explain the worktree-only contract"

    rm -rf "${fixture_root}"
    test_pass
}

run_test_beads_dolt_pilot() {
    start_timer
    test_pilot_enable_blocks_when_inventory_gate_is_blocked
    test_pilot_enable_ignores_blocked_siblings_when_current_worktree_is_ready
    test_pilot_enable_writes_mode_file_when_gate_passes
    test_pilot_review_emits_review_surface
    test_pilot_review_falls_back_to_bd_info_for_modern_cli
    test_plain_bd_blocks_sync_when_pilot_mode_is_enabled
    test_pre_commit_blocks_staged_jsonl_in_pilot_mode
    test_pilot_enable_rejects_canonical_root
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_test_beads_dolt_pilot
fi
