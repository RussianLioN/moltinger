#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib/test_helpers.sh"
source "${SCRIPT_DIR}/../lib/git_topology_fixture.sh"

seed_real_rollout_tools() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/bin" "${repo_dir}/scripts" "${repo_dir}/.githooks"
    cp "${PROJECT_ROOT}/bin/bd" "${repo_dir}/bin/bd"
    cp "${PROJECT_ROOT}/scripts/beads-resolve-db.sh" "${repo_dir}/scripts/beads-resolve-db.sh"
    cp "${PROJECT_ROOT}/scripts/beads-dolt-migration-inventory.sh" "${repo_dir}/scripts/beads-dolt-migration-inventory.sh"
    cp "${PROJECT_ROOT}/scripts/beads-dolt-pilot.sh" "${repo_dir}/scripts/beads-dolt-pilot.sh"
    cp "${PROJECT_ROOT}/scripts/beads-dolt-rollout.sh" "${repo_dir}/scripts/beads-dolt-rollout.sh"
    cp "${PROJECT_ROOT}/scripts/beads-normalize-issues-jsonl.sh" "${repo_dir}/scripts/beads-normalize-issues-jsonl.sh"
    cp "${PROJECT_ROOT}/scripts/beads-worktree-audit.sh" "${repo_dir}/scripts/beads-worktree-audit.sh"
    cp "${PROJECT_ROOT}/scripts/beads-worktree-localize.sh" "${repo_dir}/scripts/beads-worktree-localize.sh"
    cp "${PROJECT_ROOT}/scripts/worktree-ready.sh" "${repo_dir}/scripts/worktree-ready.sh"
    cp "${PROJECT_ROOT}/.githooks/pre-commit" "${repo_dir}/.githooks/pre-commit"
    cp "${PROJECT_ROOT}/.githooks/_repo-local-path.sh" "${repo_dir}/.githooks/_repo-local-path.sh"
    chmod +x \
        "${repo_dir}/bin/bd" \
        "${repo_dir}/scripts/beads-resolve-db.sh" \
        "${repo_dir}/scripts/beads-dolt-migration-inventory.sh" \
        "${repo_dir}/scripts/beads-dolt-pilot.sh" \
        "${repo_dir}/scripts/beads-dolt-rollout.sh" \
        "${repo_dir}/scripts/beads-normalize-issues-jsonl.sh" \
        "${repo_dir}/scripts/beads-worktree-audit.sh" \
        "${repo_dir}/scripts/beads-worktree-localize.sh" \
        "${repo_dir}/scripts/worktree-ready.sh" \
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

create_fake_rollout_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/rollout-fake-bd-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${FAKE_BD_MODE:-pilot-ready}"
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
    printf 'bd version 0.49.6 (rollout-fixture)\n'
    exit 0
    ;;
  "info")
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
      pilot-ready|cutover-ready)
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

run_rollout_script() {
    local repo_dir="$1"
    local fake_bin="$2"
    local fake_mode="$3"
    shift 3

    (
        cd "${repo_dir}"
        PATH="${repo_dir}/bin:${fake_bin}:$PATH" \
        BEADS_SYSTEM_BD="${fake_bin}/bd" \
        FAKE_BD_MODE="${fake_mode}" \
        ./scripts/beads-dolt-rollout.sh "$@"
    )
}

run_plain_bd() {
    local worktree_dir="$1"
    local fake_bin="$2"
    local fake_mode="$3"
    shift 3

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/bin:${fake_bin}:$PATH" \
        BEADS_SYSTEM_BD="${fake_bin}/bd" \
        FAKE_BD_MODE="${fake_mode}" \
        bd "$@"
    )
}

run_localize_script() {
    local worktree_dir="$1"
    local fake_bin="$2"
    local fake_mode="$3"
    shift 3

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/bin:${fake_bin}:$PATH" \
        BEADS_SYSTEM_BD="${fake_bin}/bd" \
        FAKE_BD_MODE="${fake_mode}" \
        ./scripts/beads-worktree-localize.sh "$@"
    )
}

run_normalize_script() {
    local worktree_dir="$1"
    local fake_bin="$2"
    local fake_mode="$3"
    shift 3

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/bin:${fake_bin}:$PATH" \
        BEADS_SYSTEM_BD="${fake_bin}/bd" \
        FAKE_BD_MODE="${fake_mode}" \
        ./scripts/beads-normalize-issues-jsonl.sh "$@"
    )
}

create_rollout_repo_fixture() {
    local fixture_root="$1"
    local repo_dir

    repo_dir="$(git_topology_fixture_create_named_repo "${fixture_root}" "moltinger")"
    git_topology_fixture_seed_beads_migration_surface_layout "${repo_dir}" pilot-ready
    git_topology_fixture_seed_pilot_ready_state "${repo_dir}"
    seed_real_rollout_tools "${repo_dir}"
    commit_fixture_state "${repo_dir}" "fixture: seed rollout repo"
    printf '%s\n' "${repo_dir}"
}

create_rollout_worktree() {
    local repo_dir="$1"
    local worktree_path="$2"
    local branch_name="$3"
    local state_mode="$4"

    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "${branch_name}" "main"
    case "${state_mode}" in
        pilot-ready)
            git_topology_fixture_seed_pilot_ready_state "${worktree_path}"
            ;;
        legacy-jsonl-first)
            git_topology_fixture_seed_legacy_jsonl_first_state "${worktree_path}"
            ;;
        *)
            printf 'unsupported rollout state mode: %s\n' "${state_mode}" >&2
            return 1
            ;;
    esac
}

seed_rollout_modern_dolt_runtime() {
    local worktree_dir="$1"

    rm -f "${worktree_dir}/.beads/beads.db"
    mkdir -p "${worktree_dir}/.beads/dolt"
}

test_rollout_report_only_summarizes_ready_and_blocked_worktrees() {
    test_start "rollout_report_only_summarizes_ready_and_blocked_worktrees"

    local fixture_root repo_dir ready_path blocked_path fake_bin report_json
    fixture_root="$(mktemp -d /tmp/beads-dolt-rollout.XXXXXX)"
    repo_dir="$(create_rollout_repo_fixture "${fixture_root}")"
    ready_path="${fixture_root}/moltinger-rollout-ready"
    blocked_path="${fixture_root}/moltinger-rollout-blocked"
    create_rollout_worktree "${repo_dir}" "${ready_path}" "feat/ready" pilot-ready
    create_rollout_worktree "${repo_dir}" "${blocked_path}" "feat/blocked" legacy-jsonl-first
    fake_bin="$(create_fake_rollout_bd_bin "${fixture_root}")"

    report_json="$(run_rollout_script "${repo_dir}" "${fake_bin}" pilot-ready report-only --format json)"

    assert_json_value "${report_json}" '.stage' "report-only" "Rollout report-only must expose the report-only stage"
    assert_json_value "${report_json}" '.inventory.pilot_gate' "pass" "Report-only must preserve a passing pilot gate for the current ready worktree"
    assert_json_value "${report_json}" '.inventory.full_cutover_gate' "blocked" "Report-only must preserve a blocked full cutover gate while blocked siblings remain"
    assert_json_value "${report_json}" '.summary.ready_count' "2" "Rollout report-only must count ready pilot candidates"
    assert_json_value "${report_json}" '.summary.blocked_count' "1" "Rollout report-only must count blocked sibling worktrees"
    assert_json_filter_count "${report_json}" '.worktrees | map(select(.rollout_stage == "ready"))' "2" "Rollout report-only must classify ready worktrees explicitly"
    assert_json_filter_count "${report_json}" '.worktrees | map(select(.rollout_stage == "blocked"))' "1" "Rollout report-only must keep blocked worktrees visible"

    rm -rf "${fixture_root}"
    test_pass
}

test_rollout_report_only_recognizes_modern_dolt_runtime() {
    test_start "rollout_report_only_recognizes_modern_dolt_runtime"

    local fixture_root repo_dir ready_path fake_bin report_json
    fixture_root="$(mktemp -d /tmp/beads-dolt-rollout.XXXXXX)"
    repo_dir="$(create_rollout_repo_fixture "${fixture_root}")"
    ready_path="${fixture_root}/moltinger-rollout-ready"
    create_rollout_worktree "${repo_dir}" "${ready_path}" "feat/ready" pilot-ready
    seed_rollout_modern_dolt_runtime "${repo_dir}"
    seed_rollout_modern_dolt_runtime "${ready_path}"
    fake_bin="$(create_fake_rollout_bd_bin "${fixture_root}")"

    report_json="$(run_rollout_script "${repo_dir}" "${fake_bin}" pilot-ready report-only --format json)"

    assert_json_value "${report_json}" '.summary.ready_count' "2" "Report-only must treat modern Dolt runtime artifacts as ready foundation"
    assert_json_value "${report_json}" '.worktrees[] | select(.branch == "feat/ready") | .db_present' "true" "Sibling worktree must report db_present when only Dolt runtime artifacts exist"
    assert_json_value "${report_json}" '.worktrees[] | select(.branch == "feat/ready") | .inventory_state' "pilot_ready_candidate" "Modern Dolt runtime must preserve pilot-ready classification"

    rm -rf "${fixture_root}"
    test_pass
}

test_rollout_cutover_creates_mode_and_rollback_package() {
    test_start "rollout_cutover_creates_mode_and_rollback_package"

    local fixture_root repo_dir ready_path fake_bin cutover_json verify_json package_dir
    fixture_root="$(mktemp -d /tmp/beads-dolt-rollout.XXXXXX)"
    repo_dir="$(create_rollout_repo_fixture "${fixture_root}")"
    ready_path="${fixture_root}/moltinger-rollout-ready"
    create_rollout_worktree "${repo_dir}" "${ready_path}" "feat/ready" pilot-ready
    fake_bin="$(create_fake_rollout_bd_bin "${fixture_root}")"

    cutover_json="$(run_rollout_script "${repo_dir}" "${fake_bin}" cutover-ready cutover --worktree "${ready_path}" --package-id demo-rollout --format json)"
    verify_json="$(run_rollout_script "${repo_dir}" "${fake_bin}" cutover-ready verify --worktree "${ready_path}" --format json)"
    package_dir="${repo_dir}/.beads/migration/rollback-packages/demo-rollout"

    assert_file_exists "${ready_path}/.beads/cutover-mode.json" "Cutover must materialize the cutover mode marker"
    assert_file_exists "${package_dir}/manifest.json" "Cutover must create a rollback package manifest"
    assert_json_value "${cutover_json}" '.stage' "controlled-cutover" "Cutover must report the controlled-cutover stage"
    assert_json_value "${cutover_json}" '.summary.cutover_count' "1" "Cutover must report one cutover target"
    assert_json_value "${verify_json}" '.stage' "verification" "Verify must expose the verification stage"
    assert_json_value "${verify_json}" '.worktrees[0].verification.verified' "true" "Verification must pass for a clean cutover worktree"
    assert_json_value "${verify_json}" '.worktrees[0].verification.legacy_sync_probe.rc' "27" "Verification must prove that legacy sync is fail-closed in cutover mode"

    rm -rf "${fixture_root}"
    test_pass
}

test_rollout_cutover_accepts_current_worktree_dot_path() {
    test_start "rollout_cutover_accepts_current_worktree_dot_path"

    local fixture_root repo_dir ready_path fake_bin cutover_json
    fixture_root="$(mktemp -d /tmp/beads-dolt-rollout.XXXXXX)"
    repo_dir="$(create_rollout_repo_fixture "${fixture_root}")"
    ready_path="${fixture_root}/ready-worktree"
    create_rollout_worktree "${repo_dir}" "${ready_path}" "feat/ready" "pilot-ready"
    ready_path="$(cd "${ready_path}" && pwd -P)"
    fake_bin="$(create_fake_rollout_bd_bin "${fixture_root}")"

    cutover_json="$(run_rollout_script "${repo_dir}" "${fake_bin}" cutover-ready cutover --worktree "${ready_path}/." --package-id dot-path --format json)"

    assert_json_value "${cutover_json}" '.summary.cutover_count' "1" "Cutover should accept --worktree . for the current ready worktree"
    assert_json_value "${cutover_json}" '.worktrees[0].path' "${ready_path}" "Dot-path cutover should normalize to the canonical worktree path"
    assert_json_value "${cutover_json}" '.worktrees[0].rollout_stage' "cutover" "Dot-path cutover should move the normalized target into cutover stage"

    rm -rf "${fixture_root}"
    test_pass
}

test_rollout_cutover_keeps_blocked_worktree_visible() {
    test_start "rollout_cutover_keeps_blocked_worktree_visible"

    local fixture_root repo_dir ready_path blocked_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-dolt-rollout.XXXXXX)"
    repo_dir="$(create_rollout_repo_fixture "${fixture_root}")"
    ready_path="${fixture_root}/moltinger-rollout-ready"
    blocked_path="${fixture_root}/moltinger-rollout-blocked"
    create_rollout_worktree "${repo_dir}" "${ready_path}" "feat/ready" pilot-ready
    create_rollout_worktree "${repo_dir}" "${blocked_path}" "feat/blocked" legacy-jsonl-first
    fake_bin="$(create_fake_rollout_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_rollout_script "${repo_dir}" "${fake_bin}" cutover-ready cutover --worktree "${ready_path}" --worktree "${blocked_path}" --package-id mixed-batch --format json 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    output="$(printf '%s\n' "${output}" | sed '/^__RC__=/d')"

    assert_eq "20" "${rc}" "Cutover must return a blocked exit code when at least one requested worktree is not ready"
    assert_file_exists "${ready_path}/.beads/cutover-mode.json" "Ready worktrees should still enter cutover in a mixed batch"
    assert_json_value "${output}" '.summary.blocked_count' "1" "Blocked targets must remain visible in cutover output"
    assert_json_filter_count "${output}" '.worktrees | map(select(.rollout_stage == "blocked"))' "1" "Blocked targets must stay in the blocked rollout stage"

    rm -rf "${fixture_root}"
    test_pass
}

test_rollout_verify_fails_on_mixed_mode_and_rollback_restores_state() {
    test_start "rollout_verify_fails_on_mixed_mode_and_rollback_restores_state"

    local fixture_root repo_dir ready_path fake_bin verify_output verify_rc rollback_json
    fixture_root="$(mktemp -d /tmp/beads-dolt-rollout.XXXXXX)"
    repo_dir="$(create_rollout_repo_fixture "${fixture_root}")"
    ready_path="${fixture_root}/moltinger-rollout-ready"
    create_rollout_worktree "${repo_dir}" "${ready_path}" "feat/ready" pilot-ready
    fake_bin="$(create_fake_rollout_bd_bin "${fixture_root}")"

    run_rollout_script "${repo_dir}" "${fake_bin}" cutover-ready cutover --worktree "${ready_path}" --package-id demo-rollback >/dev/null
    cat > "${ready_path}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"mixed-mode","status":"open","type":"task","priority":3}
EOF

    verify_output="$(
        set +e
        run_rollout_script "${repo_dir}" "${fake_bin}" cutover-ready verify --worktree "${ready_path}" --format json 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    verify_rc="$(printf '%s\n' "${verify_output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    verify_output="$(printf '%s\n' "${verify_output}" | sed '/^__RC__=/d')"

    assert_eq "21" "${verify_rc}" "Verification must fail when tracked issues.jsonl recreates mixed mode during cutover"
    assert_contains "${verify_output}" "recreate mixed mode" "Verification must explain the mixed-mode failure explicitly"

    rollback_json="$(run_rollout_script "${repo_dir}" "${fake_bin}" cutover-ready rollback --package-id demo-rollback --format json)"

    assert_json_value "${rollback_json}" '.stage' "rollback" "Rollback must expose the rollback stage"
    assert_file_exists "${ready_path}/.beads/rollback-state.json" "Rollback must preserve explicit rollback evidence in the target worktree"
    if [[ -f "${ready_path}/.beads/cutover-mode.json" ]]; then
        test_fail "Rollback must remove the active cutover marker"
    fi
    if [[ -f "${ready_path}/.beads/issues.jsonl" ]]; then
        test_fail "Rollback must restore the pre-cutover file set instead of keeping mixed-mode residue"
    fi
    assert_json_value "${rollback_json}" '.summary.rolled_back_count' "1" "Rollback output must report the rolled-back target"

    rm -rf "${fixture_root}"
    test_pass
}

test_rollout_cutover_blocks_legacy_helpers_and_sync() {
    test_start "rollout_cutover_blocks_legacy_helpers_and_sync"

    local fixture_root repo_dir ready_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/beads-dolt-rollout.XXXXXX)"
    repo_dir="$(create_rollout_repo_fixture "${fixture_root}")"
    ready_path="${fixture_root}/moltinger-rollout-ready"
    create_rollout_worktree "${repo_dir}" "${ready_path}" "feat/ready" pilot-ready
    fake_bin="$(create_fake_rollout_bd_bin "${fixture_root}")"

    run_rollout_script "${repo_dir}" "${fake_bin}" cutover-ready cutover --worktree "${ready_path}" --package-id helper-blocks >/dev/null

    output="$(
        set +e
        run_plain_bd "${ready_path}" "${fake_bin}" cutover-ready sync 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "27" "${rc}" "Cutover mode must fail closed on legacy sync"
    assert_contains "${output}" "cutover mode is enabled" "Cutover sync block must identify the active migration mode"

    output="$(
        set +e
        run_normalize_script "${ready_path}" "${fake_bin}" cutover-ready --path "${ready_path}/.beads/issues.jsonl" 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "24" "${rc}" "Cutover mode must retire direct JSONL normalization"
    assert_contains "${output}" "Cutover mode retires tracked .beads/issues.jsonl normalization" "Cutover normalizer block must explain the retirement path"

    output="$(
        set +e
        run_localize_script "${ready_path}" "${fake_bin}" cutover-ready --path . 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"
    assert_eq "23" "${rc}" "Cutover mode must retire the localization helper for an already-migrated worktree"
    assert_contains "${output}" "Cutover mode is already active" "Localization helper must explain why it is retired in cutover mode"

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    test_rollout_report_only_summarizes_ready_and_blocked_worktrees
    test_rollout_report_only_recognizes_modern_dolt_runtime
    test_rollout_cutover_creates_mode_and_rollback_package
    test_rollout_cutover_accepts_current_worktree_dot_path
    test_rollout_cutover_keeps_blocked_worktree_visible
    test_rollout_verify_fails_on_mixed_mode_and_rollback_restores_state
    test_rollout_cutover_blocks_legacy_helpers_and_sync
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
