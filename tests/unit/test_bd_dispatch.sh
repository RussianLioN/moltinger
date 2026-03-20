#!/bin/bash
# Unit tests for repo-local plain `bd` dispatch and Beads ownership localization.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

create_fake_system_bd_bin() {
    local fixture_root="$1"
    local fake_bin="${fixture_root}/system-bd-bin"

    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

db_path=""
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
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ -n "${db_path}" ]]; then
  mkdir -p "$(dirname "${db_path}")"
  : > "${db_path}"
fi

printf 'DB=%s\n' "${db_path}"
printf 'ARGS=%s\n' "${args[*]}"
EOF
    chmod +x "${fake_bin}/bd"

    printf '%s\n' "${fake_bin}"
}

seed_repo_local_bd_tools() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/bin" "${repo_dir}/scripts"
    cp "${PROJECT_ROOT}/bin/bd" "${repo_dir}/bin/bd"
    cp "${PROJECT_ROOT}/scripts/beads-resolve-db.sh" "${repo_dir}/scripts/beads-resolve-db.sh"
    cp "${PROJECT_ROOT}/scripts/beads-worktree-localize.sh" "${repo_dir}/scripts/beads-worktree-localize.sh"
    chmod +x "${repo_dir}/bin/bd" "${repo_dir}/scripts/beads-resolve-db.sh" "${repo_dir}/scripts/beads-worktree-localize.sh"

    (
        cd "${repo_dir}"
        git add bin/bd scripts/beads-resolve-db.sh scripts/beads-worktree-localize.sh
        git commit -m "fixture: seed repo-local bd tools" >/dev/null
    )
}

seed_local_beads_foundation() {
    local worktree_dir="$1"

    mkdir -p "${worktree_dir}/.beads"
    cat > "${worktree_dir}/.beads/config.yaml" <<'EOF'
issue-prefix: "demo"
auto-start-daemon: false
EOF
    cat > "${worktree_dir}/.beads/issues.jsonl" <<'EOF'
{"id":"demo-1","title":"seed","status":"open","type":"task","priority":3}
EOF
}

run_plain_bd() {
    local worktree_dir="$1"
    local fake_bin="$2"
    shift 2

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/bin:${fake_bin}:$PATH" bd "$@"
    )
}

run_localize() {
    local worktree_dir="$1"
    local fake_bin="$2"
    shift 2

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/bin:${fake_bin}:$PATH" ./scripts/beads-worktree-localize.sh "$@"
    )
}

canonicalize_path() {
    local target_path="$1"

    (
        cd "${target_path}"
        pwd -P
    )
}

test_plain_bd_executes_against_worktree_local_db() {
    test_start "plain_bd_executes_against_worktree_local_db"

    local fixture_root repo_dir worktree_path fake_bin output expected_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-safe-worktree"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/safe-local" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_local_beads_foundation "${worktree_path}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    expected_db="${worktree_path}/.beads/beads.db"

    output="$(run_plain_bd "${worktree_path}" "${fake_bin}" info)"

    assert_contains "${output}" "DB=${expected_db}" "Plain bd should pin the local worktree DB"
    assert_contains "${output}" "ARGS=info" "Plain bd should forward the original arguments"

    rm -rf "${fixture_root}"
    test_pass
}

test_canonical_root_plain_bd_allows_read_only_commands() {
    test_start "canonical_root_plain_bd_allows_read_only_commands"

    local fixture_root repo_dir fake_bin output
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(run_plain_bd "${repo_dir}" "${fake_bin}" info)"

    assert_contains "${output}" "DB=" "Canonical-root read-only commands should still pass through to bd"
    assert_contains "${output}" "ARGS=info" "Canonical-root read-only commands should preserve the original subcommand"

    rm -rf "${fixture_root}"
    test_pass
}

test_canonical_root_plain_bd_blocks_mutation_by_default() {
    test_start "canonical_root_plain_bd_blocks_mutation_by_default"

    local fixture_root repo_dir fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${repo_dir}" "${fake_bin}" update demo-1 --status in_progress 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "26" "${rc}" "Canonical-root mutating plain bd should fail closed by default"
    assert_contains "${output}" "mutating canonical-root tracker commands are blocked by default" "Blocked root mutation should explain the new policy"
    assert_contains "${output}" "bd --db" "Blocked root mutation should point to the explicit override path"

    rm -rf "${fixture_root}"
    test_pass
}

test_canonical_root_plain_bd_allows_explicit_root_db_override() {
    test_start "canonical_root_plain_bd_allows_explicit_root_db_override"

    local fixture_root repo_dir fake_bin output explicit_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    explicit_db="${repo_dir}/.beads/beads.db"

    output="$(run_plain_bd "${repo_dir}" "${fake_bin}" --db "${explicit_db}" update demo-1 --status in_progress)"

    assert_contains "${output}" "DB=${explicit_db}" "Explicit canonical-root DB override should be allowed"
    assert_contains "${output}" "ARGS=update demo-1 --status in_progress" "Explicit canonical-root DB override should preserve the mutating command"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_legacy_redirect() {
    test_start "plain_bd_blocks_legacy_redirect"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-legacy-worktree"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/legacy-localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_local_beads_foundation "${worktree_path}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${worktree_path}" "${fake_bin}" update demo-1 --status in_progress 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "${rc}" "Legacy redirect should fail closed"
    assert_contains "${output}" "legacy Beads redirect metadata" "Blocked dispatch should explain the redirect failure"
    assert_contains "${output}" "beads-worktree-localize.sh" "Blocked dispatch should point to the localization helper"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_blocks_root_fallback_when_local_foundation_is_missing() {
    test_start "plain_bd_blocks_root_fallback_when_local_foundation_is_missing"

    local fixture_root repo_dir worktree_path fake_bin output rc
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    : > "${repo_dir}/.beads/beads.db"
    worktree_path="${fixture_root}/moltinger-missing-local"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/missing-local" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        set +e
        run_plain_bd "${worktree_path}" "${fake_bin}" update demo-1 --status in_progress 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "24" "${rc}" "Missing local foundation in a dedicated worktree should block canonical-root fallback"
    assert_contains "${output}" "falling back to the canonical root tracker is blocked" "Blocked dispatch should name the root-fallback failure"

    rm -rf "${fixture_root}"
    test_pass
}

test_plain_bd_allows_explicit_troubleshooting_flags() {
    test_start "plain_bd_allows_explicit_troubleshooting_flags"

    local fixture_root repo_dir worktree_path fake_bin output explicit_db
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-explicit-troubleshooting"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/explicit-troubleshooting" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"
    explicit_db="${fixture_root}/custom-explicit.db"

    output="$(run_plain_bd "${worktree_path}" "${fake_bin}" --db "${explicit_db}" info)"

    assert_contains "${output}" "DB=${explicit_db}" "Explicit troubleshooting DB path should pass through unchanged"
    assert_contains "${output}" "ARGS=info" "Explicit troubleshooting should still forward the subcommand"

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_materializes_local_db_and_removes_redirect() {
    test_start "localize_materializes_local_db_and_removes_redirect"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    worktree_path="${fixture_root}/moltinger-localize"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    seed_local_beads_foundation "${worktree_path}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(run_localize "${worktree_path}" "${fake_bin}" --path "${worktree_path}")"

    assert_contains "${output}" "State: current" "Localization should end in the current localized state"
    if [[ -f "${worktree_path}/.beads/redirect" ]]; then
        test_fail "Localization should remove legacy redirect metadata"
    fi
    if [[ ! -f "${worktree_path}/.beads/beads.db" ]]; then
        test_fail "Localization should materialize the local beads.db"
    fi

    rm -rf "${fixture_root}"
    test_pass
}

test_localize_bootstraps_missing_foundation_from_source_ref() {
    test_start "localize_bootstraps_missing_foundation_from_source_ref"

    local fixture_root repo_dir worktree_path fake_bin output
    fixture_root="$(mktemp -d /tmp/bd-dispatch-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    seed_repo_local_bd_tools "${repo_dir}"
    seed_local_beads_foundation "${repo_dir}"
    printf 'export PATH="${repo_root}/bin:${PATH}"\n' > "${repo_dir}/.envrc"
    (
        cd "${repo_dir}"
        git add .beads/config.yaml .beads/issues.jsonl .envrc
        git commit -m "fixture: seed bootstrap foundation" >/dev/null
    )
    worktree_path="${fixture_root}/moltinger-bootstrap-localize"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/bootstrap-localize" "main"
    worktree_path="$(canonicalize_path "${worktree_path}")"
    rm -f \
        "${worktree_path}/.beads/config.yaml" \
        "${worktree_path}/.beads/issues.jsonl" \
        "${worktree_path}/bin/bd" \
        "${worktree_path}/scripts/beads-resolve-db.sh" \
        "${worktree_path}/scripts/beads-worktree-localize.sh" \
        "${worktree_path}/.envrc"
    mkdir -p "${worktree_path}/.beads"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"
    fake_bin="$(create_fake_system_bd_bin "${fixture_root}")"

    output="$(
        cd "${PROJECT_ROOT}"
        PATH="${PROJECT_ROOT}/bin:${fake_bin}:$PATH" ./scripts/beads-worktree-localize.sh --path "${worktree_path}" --bootstrap-source main
    )"

    assert_contains "${output}" "State: current" "Bootstrap localization should finish in the current localized state"
    assert_contains "${output}" "Bootstrap Source: main" "Bootstrap localization should report the source ref"
    if [[ -f "${worktree_path}/.beads/redirect" ]]; then
        test_fail "Bootstrap localization should remove legacy redirect metadata"
    fi
    if [[ ! -f "${worktree_path}/.beads/config.yaml" || ! -f "${worktree_path}/.beads/issues.jsonl" ]]; then
        test_fail "Bootstrap localization should restore the local Beads foundation"
    fi
    if [[ ! -f "${worktree_path}/bin/bd" || ! -f "${worktree_path}/scripts/beads-resolve-db.sh" ]]; then
        test_fail "Bootstrap localization should restore the plain bd toolchain"
    fi
    if [[ ! -f "${worktree_path}/.beads/beads.db" ]]; then
        test_fail "Bootstrap localization should materialize the local beads.db"
    fi

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Plain bd Dispatch Unit Tests"
        echo "========================================="
        echo ""
    fi

    test_plain_bd_executes_against_worktree_local_db
    test_canonical_root_plain_bd_allows_read_only_commands
    test_canonical_root_plain_bd_blocks_mutation_by_default
    test_canonical_root_plain_bd_allows_explicit_root_db_override
    test_plain_bd_blocks_legacy_redirect
    test_plain_bd_blocks_root_fallback_when_local_foundation_is_missing
    test_plain_bd_allows_explicit_troubleshooting_flags
    test_localize_materializes_local_db_and_removes_redirect
    test_localize_bootstraps_missing_foundation_from_source_ref
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
