#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

WRAPPER_SCRIPT="$PROJECT_ROOT/scripts/bd-local.sh"

install_fake_bd() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/bin" "${repo_dir}/scripts" "${repo_dir}/.fake-system-bd"
    cat > "${repo_dir}/bin/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BEADS_DB=%s\n' "${BEADS_DB:-}"
printf 'ARGS=%s\n' "$*"
EOF
    chmod +x "${repo_dir}/bin/bd"
    cat > "${repo_dir}/.fake-system-bd/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
    chmod +x "${repo_dir}/.fake-system-bd/bd"
    cp "${PROJECT_ROOT}/scripts/beads-resolve-db.sh" "${repo_dir}/scripts/beads-resolve-db.sh"
    chmod +x "${repo_dir}/scripts/beads-resolve-db.sh"
}

run_wrapper() {
    local worktree_dir="$1"
    shift

    (
        cd "${worktree_dir}"
        PATH="${worktree_dir}/.fake-system-bd:${PATH}" \
        BEADS_SYSTEM_BD="${worktree_dir}/.fake-system-bd/bd" \
        "${WRAPPER_SCRIPT}" "$@"
    )
}

seed_local_beads_state() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "demo"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"demo-1","title":"seed"}\n' > "${repo_dir}/.beads/issues.jsonl"
}

seed_post_migration_runtime_state() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads/beads.db" "${repo_dir}/.beads/dolt/beads/.dolt"
    printf 'issue-prefix: "demo"\n' > "${repo_dir}/.beads/config.yaml"
}

seed_broken_post_migration_runtime_state() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads/dolt/.dolt"
    printf 'issue-prefix: "demo"\n' > "${repo_dir}/.beads/config.yaml"
}

test_bd_local_exports_worktree_local_beads_db() {
    test_start "bd_local_exports_worktree_local_beads_db"

    local fixture_root repo_dir worktree_path physical_repo_dir output
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_path="${fixture_root}/moltinger-safe"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/safe-local" "main"

    install_fake_bd "${worktree_path}"
    seed_local_beads_state "${worktree_path}"
    physical_repo_dir="$(cd "${worktree_path}" && pwd -P)"

    output="$(
        run_wrapper "${worktree_path}" status
    )"

    assert_contains "${output}" "BEADS_DB=${physical_repo_dir}/.beads/beads.db" "Wrapper must pin BEADS_DB to the current worktree"
    assert_contains "${output}" "ARGS=status" "Wrapper must forward the original bd arguments"

    rm -rf "${fixture_root}"
    test_pass
}

test_bd_local_blocks_redirected_worktrees() {
    test_start "bd_local_blocks_redirected_worktrees"

    local fixture_root repo_dir worktree_path output rc
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_path="${fixture_root}/moltinger-redirected"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/redirected" "main"

    install_fake_bd "${worktree_path}"
    seed_local_beads_state "${worktree_path}"
    printf '%s\n' "${repo_dir}/.beads" > "${worktree_path}/.beads/redirect"

    output="$(
        set +e
        run_wrapper "${worktree_path}" status 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "23" "${rc}" "Wrapper must fail closed when redirect metadata is present"
    assert_contains "${output}" "legacy Beads redirect metadata" "Wrapper must explain the redirect ownership failure"
    assert_contains "${output}" "beads-worktree-localize.sh" "Wrapper must point operators to localization when redirect metadata exists"

    rm -rf "${fixture_root}"
    test_pass
}

test_bd_local_blocks_missing_foundation_files() {
    test_start "bd_local_blocks_missing_foundation_files"

    local fixture_root repo_dir worktree_path output rc
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_path="${fixture_root}/moltinger-missing"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/missing" "main"

    install_fake_bd "${worktree_path}"
    mkdir -p "${worktree_path}/.beads"

    output="$(
        set +e
        run_wrapper "${worktree_path}" status 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "25" "${rc}" "Wrapper must fail closed when local Beads foundation files are missing"
    assert_contains "${output}" ".beads/config.yaml" "Wrapper must report missing config.yaml"
    assert_contains "${output}" ".beads/issues.jsonl" "Wrapper must report missing issues.jsonl"

    rm -rf "${fixture_root}"
    test_pass
}

test_bd_local_allows_readonly_post_migration_runtime_without_issues_jsonl() {
    test_start "bd_local_allows_readonly_post_migration_runtime_without_issues_jsonl"

    local fixture_root repo_dir worktree_path physical_repo_dir output
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_path="${fixture_root}/moltinger-post-migration-runtime"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/post-migration-runtime" "main"

    install_fake_bd "${worktree_path}"
    seed_post_migration_runtime_state "${worktree_path}"
    physical_repo_dir="$(cd "${worktree_path}" && pwd -P)"

    output="$(
        run_wrapper "${worktree_path}" status
    )"

    assert_contains "${output}" "BEADS_DB=${physical_repo_dir}/.beads/beads.db" "Wrapper must keep using the local runtime after tracked JSONL retirement"
    assert_contains "${output}" "ARGS=status" "Wrapper must preserve the read-only command in post-migration runtime-only state"

    rm -rf "${fixture_root}"
    test_pass
}

test_bd_local_blocks_deprecated_sync_with_modern_guidance() {
    test_start "bd_local_blocks_deprecated_sync_with_modern_guidance"

    local fixture_root repo_dir worktree_path output rc
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_path="${fixture_root}/moltinger-runtime-only-sync"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/runtime-only-sync" "main"

    install_fake_bd "${worktree_path}"
    seed_post_migration_runtime_state "${worktree_path}"

    output="$(
        set +e
        run_wrapper "${worktree_path}" sync 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "28" "${rc}" "bd-local must surface deprecated sync guidance instead of suggesting pilot mode"
    assert_contains "${output}" "'sync' is retired" "bd-local must explain that bd sync is retired"
    assert_contains "${output}" "bd dolt push / bd dolt pull" "bd-local must point operators to the modern Dolt workflow"

    rm -rf "${fixture_root}"
    test_pass
}

test_bd_local_blocks_broken_runtime_only_state_with_bootstrap_guidance() {
    test_start "bd_local_blocks_broken_runtime_only_state_with_bootstrap_guidance"

    local fixture_root repo_dir worktree_path output rc
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"
    worktree_path="${fixture_root}/moltinger-broken-runtime"
    git_topology_fixture_add_worktree_branch_from "${repo_dir}" "${worktree_path}" "feat/broken-runtime" "main"

    install_fake_bd "${worktree_path}"
    seed_broken_post_migration_runtime_state "${worktree_path}"

    output="$(
        set +e
        run_wrapper "${worktree_path}" status 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "25" "${rc}" "bd-local must fail closed when the Dolt runtime exists only as an incomplete shell"
    assert_contains "${output}" "local Dolt-backed Beads runtime is incomplete" "bd-local must describe the failure as a runtime repair problem"
    assert_contains "${output}" "Tracked .beads/issues.jsonl is retired here" "bd-local must not ask operators to restore retired JSONL"
    assert_contains "${output}" "./scripts/beads-worktree-localize.sh --path ." "bd-local must point operators to the managed runtime repair helper for runtime-only failures"

    rm -rf "${fixture_root}"
    test_pass
}

run_all_tests() {
    start_timer

    if [[ "$OUTPUT_JSON" != "true" ]]; then
        echo ""
        echo "========================================="
        echo "  Beads Local Wrapper Unit Tests"
        echo "========================================="
        echo ""
    fi

    if [[ ! -x "$WRAPPER_SCRIPT" ]]; then
        test_fail "Wrapper script missing or not executable: $WRAPPER_SCRIPT"
        generate_report
        return 1
    fi

    test_bd_local_exports_worktree_local_beads_db
    test_bd_local_blocks_redirected_worktrees
    test_bd_local_blocks_missing_foundation_files
    test_bd_local_allows_readonly_post_migration_runtime_without_issues_jsonl
    test_bd_local_blocks_deprecated_sync_with_modern_guidance
    test_bd_local_blocks_broken_runtime_only_state_with_bootstrap_guidance
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
