#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"
source "$SCRIPT_DIR/../lib/git_topology_fixture.sh"

WRAPPER_SCRIPT="$PROJECT_ROOT/scripts/bd-local.sh"

install_fake_bd() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/bin"
    cat > "${repo_dir}/bin/bd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BEADS_DB=%s\n' "${BEADS_DB:-}"
printf 'ARGS=%s\n' "$*"
EOF
    chmod +x "${repo_dir}/bin/bd"
}

seed_local_beads_state() {
    local repo_dir="$1"

    mkdir -p "${repo_dir}/.beads"
    printf 'issue-prefix: "demo"\n' > "${repo_dir}/.beads/config.yaml"
    printf '{"id":"demo-1","title":"seed"}\n' > "${repo_dir}/.beads/issues.jsonl"
}

test_bd_local_exports_worktree_local_beads_db() {
    test_start "bd_local_exports_worktree_local_beads_db"

    local fixture_root repo_dir physical_repo_dir output
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"

    install_fake_bd "${repo_dir}"
    seed_local_beads_state "${repo_dir}"
    physical_repo_dir="$(cd "${repo_dir}" && pwd -P)"

    output="$(
        cd "${repo_dir}"
        "${WRAPPER_SCRIPT}" sync
    )"

    assert_contains "${output}" "BEADS_DB=${physical_repo_dir}/.beads/beads.db" "Wrapper must pin BEADS_DB to the current worktree"
    assert_contains "${output}" "ARGS=sync" "Wrapper must forward the original bd arguments"

    rm -rf "${fixture_root}"
    test_pass
}

test_bd_local_blocks_redirected_worktrees() {
    test_start "bd_local_blocks_redirected_worktrees"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"

    install_fake_bd "${repo_dir}"
    seed_local_beads_state "${repo_dir}"
    printf '%s\n' "${fixture_root}/canonical-root/.beads" > "${repo_dir}/.beads/redirect"

    output="$(
        set +e
        cd "${repo_dir}"
        "${WRAPPER_SCRIPT}" sync 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "3" "${rc}" "Wrapper must fail closed when redirect metadata is present"
    assert_contains "${output}" "beads-worktree-localize.sh" "Wrapper must point operators to localization when redirect metadata exists"

    rm -rf "${fixture_root}"
    test_pass
}

test_bd_local_blocks_missing_foundation_files() {
    test_start "bd_local_blocks_missing_foundation_files"

    local fixture_root repo_dir output rc
    fixture_root="$(mktemp -d /tmp/bd-local-unit.XXXXXX)"
    repo_dir="$(git_topology_fixture_create_named_repo "$fixture_root" "moltinger")"

    install_fake_bd "${repo_dir}"
    mkdir -p "${repo_dir}/.beads"

    output="$(
        set +e
        cd "${repo_dir}"
        "${WRAPPER_SCRIPT}" sync 2>&1
        printf '\n__RC__=%s\n' "$?"
    )"
    rc="$(printf '%s\n' "${output}" | awk -F= '/__RC__/ {print $2}' | tail -1)"

    assert_eq "4" "${rc}" "Wrapper must fail closed when local Beads foundation files are missing"
    assert_contains "${output}" ".beads/config.yaml" "Wrapper must report missing config.yaml"
    assert_contains "${output}" ".beads/issues.jsonl" "Wrapper must report missing issues.jsonl"

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
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
