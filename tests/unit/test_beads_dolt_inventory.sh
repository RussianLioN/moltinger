#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib/test_helpers.sh"
source "${SCRIPT_DIR}/../lib/git_topology_fixture.sh"

seed_inventory_script() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/scripts"
    cp "${PROJECT_ROOT}/scripts/beads-dolt-migration-inventory.sh" "${repo_dir}/scripts/beads-dolt-migration-inventory.sh"
    chmod +x "${repo_dir}/scripts/beads-dolt-migration-inventory.sh"
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

create_fake_inventory_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/fake-bd-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${FAKE_BD_MODE:-legacy}"
cwd="$(pwd -P)"

if [[ "${cwd}" == *"/.git/worktrees/"* ]]; then
  cwd="$(cd "${cwd}/../../.." && pwd -P)"
fi

repo_root="$(git -C "${cwd}" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "${cwd}")"
canonical_root="$(cd "${repo_root}" && cd "$(git rev-parse --git-common-dir)/.." && pwd -P)"

if [[ "${1:-}" == "--version" ]]; then
  printf 'bd version 0.49.6 (fixture)\n'
  exit 0
fi

if [[ "${1:-}" == "--no-daemon" && "${2:-}" == "info" ]]; then
  case "${mode}" in
    legacy|blocked-sibling|bootstrap-variance)
      db_path="${repo_root}/.beads/beads.db"
      ;;
    pilot-ready)
      db_path="${repo_root}/.beads/beads.db"
      ;;
    *)
      db_path="${repo_root}/.beads/beads.db"
      ;;
  esac
  cat <<EOT
Beads Database Information
===========================
Database: ${db_path}
Mode: direct

Daemon Status:
  Connected: no
  Reason: flag_no_daemon
EOT
  exit 0
fi

if [[ "${1:-}" == "backend" && "${2:-}" == "show" ]]; then
  case "${mode}" in
    legacy|blocked-sibling|bootstrap-variance)
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
fi

printf 'unsupported fake bd arguments: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

run_inventory() {
    local repo_dir="$1"
    local fake_bin="$2"
    local fake_mode="$3"
    shift 3

    (
        cd "${repo_dir}"
        PATH="${repo_dir}/bin:${fake_bin}:$PATH" \
        BEADS_SYSTEM_BD="${fake_bin}/bd" \
        FAKE_BD_MODE="${fake_mode}" \
        ./scripts/beads-dolt-migration-inventory.sh "$@"
    )
}

test_inventory_reports_blocked_legacy_baseline() {
    test_start "inventory_reports_blocked_legacy_baseline"

    local fixture_root repo_dir fake_bin json
    fixture_root="$(mktemp -d /tmp/beads-dolt-inventory.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    git_topology_fixture_seed_beads_migration_surface_layout "${repo_dir}" legacy
    git_topology_fixture_seed_legacy_jsonl_first_state "${repo_dir}"
    seed_inventory_script "${repo_dir}"
    commit_fixture_state "${repo_dir}" "fixture: seed legacy inventory state"
    fake_bin="$(create_fake_inventory_bd_bin "${fixture_root}")"

    json="$(run_inventory "${repo_dir}" "${fake_bin}" legacy --format json)"

    assert_json_value "${json}" '.summary.verdict' "blocked" "Legacy inventory baseline must be blocked"
    assert_json_value "${json}" '.summary.pilot_gate' "blocked" "Pilot gate must stay blocked on legacy baseline"
    assert_json_value "${json}" '.surfaces[] | select(.id == "tracked.issues_jsonl") | .classification' "must-migrate" "Tracked issues.jsonl must classify as must-migrate"
    assert_json_value "${json}" '.surfaces[] | select(.id == "runtime.backend_state") | .classification' "blocked" "SQLite backend with canonical-root coupling must be a blocker"
    assert_json_value "${json}" '.worktrees[] | select(.current == true) | .state' "legacy_jsonl_first" "Current worktree must classify as legacy_jsonl_first"

    rm -rf "${fixture_root}"
    test_pass
}

test_inventory_detects_runtime_coupling_and_surface_blockers() {
    test_start "inventory_detects_runtime_coupling_and_surface_blockers"

    local fixture_root repo_dir fake_bin json
    fixture_root="$(mktemp -d /tmp/beads-dolt-inventory.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    git_topology_fixture_seed_beads_migration_surface_layout "${repo_dir}" legacy
    git_topology_fixture_seed_legacy_jsonl_first_state "${repo_dir}"
    seed_inventory_script "${repo_dir}"
    commit_fixture_state "${repo_dir}" "fixture: seed runtime coupling state"
    fake_bin="$(create_fake_inventory_bd_bin "${fixture_root}")"

    json="$(run_inventory "${repo_dir}" "${fake_bin}" legacy --format json)"

    assert_json_value "${json}" '.surfaces[] | select(.id == "runtime.command_path") | .classification' "can-bridge" "Repo-local bd shim should classify as can-bridge"
    assert_json_value "${json}" '.surfaces[] | select(.id == "hook.pre_commit") | .classification' "must-migrate" "Legacy pre-commit hook should classify as must-migrate"
    assert_json_value "${json}" '.surfaces[] | select(.id == "doc.quickstart_ru") | .classification' "must-migrate" "Legacy quickstart must classify as must-migrate"
    assert_json_value "${json}" '.surfaces[] | select(.id == "tracked.config_yaml") | .classification' "can-bridge" "Tracked config should classify as can-bridge"
    assert_json_array_contains "${json}" '.blockers | map(.id)' "runtime.backend_state" "Backend coupling must appear in blocker ids"

    rm -rf "${fixture_root}"
    test_pass
}

test_inventory_is_deterministic_across_repeated_runs() {
    test_start "inventory_is_deterministic_across_repeated_runs"

    local fixture_root repo_dir fake_bin first_json second_json
    fixture_root="$(mktemp -d /tmp/beads-dolt-inventory.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    git_topology_fixture_seed_beads_migration_surface_layout "${repo_dir}" legacy
    git_topology_fixture_seed_legacy_jsonl_first_state "${repo_dir}"
    seed_inventory_script "${repo_dir}"
    commit_fixture_state "${repo_dir}" "fixture: seed deterministic inventory state"
    fake_bin="$(create_fake_inventory_bd_bin "${fixture_root}")"

    first_json="$(run_inventory "${repo_dir}" "${fake_bin}" legacy --format json)"
    second_json="$(run_inventory "${repo_dir}" "${fake_bin}" legacy --format json)"

    assert_eq "${first_json}" "${second_json}" "Repeated inventory runs must stay byte-for-byte deterministic on unchanged input"

    rm -rf "${fixture_root}"
    test_pass
}

test_inventory_detects_blocked_sibling_and_bootstrap_variance() {
    test_start "inventory_detects_blocked_sibling_and_bootstrap_variance"

    local fixture_root repo_dir blocked_worktree bootstrap_worktree fake_bin json
    fixture_root="$(mktemp -d /tmp/beads-dolt-inventory.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    git_topology_fixture_seed_beads_migration_surface_layout "${repo_dir}" legacy
    git_topology_fixture_seed_legacy_jsonl_first_state "${repo_dir}"
    seed_inventory_script "${repo_dir}"
    commit_fixture_state "${repo_dir}" "fixture: seed sibling inventory state"
    blocked_worktree="${fixture_root}/moltinger-blocked"
    bootstrap_worktree="${fixture_root}/moltinger-bootstrap"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${blocked_worktree}" "feat/blocked" "main"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${bootstrap_worktree}" "feat/bootstrap" "main"
    blocked_worktree="$(cd "${blocked_worktree}" && pwd -P)"
    bootstrap_worktree="$(cd "${bootstrap_worktree}" && pwd -P)"
    git_topology_fixture_seed_blocked_sibling_state "${blocked_worktree}" "${repo_dir}"
    git_topology_fixture_seed_bootstrap_variance_state "${bootstrap_worktree}" "${repo_dir}"
    fake_bin="$(create_fake_inventory_bd_bin "${fixture_root}")"

    json="$(run_inventory "${repo_dir}" "${fake_bin}" blocked-sibling --format json)"

    assert_json_filter_count "${json}" '.worktrees | map(select(.state == "migratable_legacy"))' "1" "Inventory must detect one blocked sibling with redirect residue"
    assert_json_filter_count "${json}" '.worktrees | map(select(.state == "bootstrap_variance"))' "1" "Inventory must detect one bootstrap-variance sibling"
    assert_json_array_contains "${json}" '.blockers | map(.id)' "worktree:${blocked_worktree}" "Blocked sibling must appear in blocker ids"
    assert_json_array_contains "${json}" '.blockers | map(.id)' "worktree:${bootstrap_worktree}" "Bootstrap-variance sibling must appear in blocker ids"

    rm -rf "${fixture_root}"
    test_pass
}

test_inventory_machine_readable_report_can_pass_pilot_gate() {
    test_start "inventory_machine_readable_report_can_pass_pilot_gate"

    local fixture_root repo_dir fake_bin json gate_output gate_rc
    fixture_root="$(mktemp -d /tmp/beads-dolt-inventory.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    git_topology_fixture_seed_beads_migration_surface_layout "${repo_dir}" pilot-ready
    git_topology_fixture_seed_pilot_ready_state "${repo_dir}"
    seed_inventory_script "${repo_dir}"
    commit_fixture_state "${repo_dir}" "fixture: seed pilot-ready inventory state"
    fake_bin="$(create_fake_inventory_bd_bin "${fixture_root}")"

    json="$(run_inventory "${repo_dir}" "${fake_bin}" pilot-ready --format json)"
    gate_output="$(
        set +e
        run_inventory "${repo_dir}" "${fake_bin}" pilot-ready --format env --gate pilot 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    gate_rc="$(printf '%s\n' "${gate_output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_json_value "${json}" '.summary.verdict' "warning" "Pilot-ready fixture may still carry bridge warnings"
    assert_json_value "${json}" '.summary.pilot_gate' "pass" "Pilot-ready fixture must pass the pilot gate when blockers are absent"
    assert_json_value "${json}" '.surfaces[] | select(.id == "runtime.backend_state") | .classification' "already-compatible" "Pilot-ready runtime backend must classify as compatible"
    assert_eq "0" "${gate_rc}" "Pilot gate should exit successfully when blockers are absent"
    assert_contains "${gate_output}" "pilot_gate=pass" "Env output must expose pilot gate result"

    rm -rf "${fixture_root}"
    test_pass
}

run_test_beads_dolt_inventory() {
    start_timer
    test_inventory_reports_blocked_legacy_baseline
    test_inventory_detects_runtime_coupling_and_surface_blockers
    test_inventory_is_deterministic_across_repeated_runs
    test_inventory_detects_blocked_sibling_and_bootstrap_variance
    test_inventory_machine_readable_report_can_pass_pilot_gate
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_test_beads_dolt_inventory
fi
